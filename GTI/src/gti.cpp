// GTI
// Created by Ruiyao Ma on 24-02-22

#include "gti.h"
#include <cstdlib>
#include <cstring>
#include <iomanip>
#include <random>
#include <numeric>
#include <limits>
#include <tuple>
#include <unordered_map>
#include <unordered_set>

namespace {

// Find leaf node and entry index for `target_oid` inside subtree rooted at `subroot`.
static bool findLeafEidForOidInSubtree(GTI_Node *subroot, unsigned target_oid, GTI_Node *&leaf, unsigned &eid)
{
    if (subroot == nullptr)
        return false;
    if (subroot->type == 1)
    {
        for (unsigned m = 0; m < subroot->entries.size(); ++m)
        {
            if (subroot->entries[m] != nullptr && (unsigned)subroot->entries[m]->oid == target_oid)
            {
                leaf = subroot;
                eid = m;
                return true;
            }
        }
        return false;
    }
    for (GTI_Entry *e : subroot->entries)
    {
        if (e != nullptr && e->child != nullptr && findLeafEidForOidInSubtree(e->child, target_oid, leaf, eid))
            return true;
    }
    return false;
}

// Collect all data object ids stored in leaves under `node` (internal or leaf root).
void collectLeafOidsUnderNode(GTI_Node *node, std::vector<unsigned> &out)
{
    if (node == nullptr)
        return;
    if (node->type == 1)
    {
        for (GTI_Entry *e : node->entries)
            if (e != nullptr)
                out.push_back(e->oid);
        return;
    }
    for (GTI_Entry *e : node->entries)
        if (e != nullptr && e->child != nullptr)
            collectLeafOidsUnderNode(e->child, out);
}

// Shallow graph (graph_level_offset>1): need many graph seeds before subtree expansion.
// Env: GTI_SHALLOW_GRAPH_K_MULT (default 64), GTI_SHALLOW_GRAPH_SEARCH_K_CAP (default 8192), GTI_SHALLOW_GRAPH_EF_MIN.
unsigned shallowGraphSearchK(unsigned L, size_t num_graph_vertices)
{
    if (num_graph_vertices == 0)
        return L;
    unsigned mult = 64;
    if (const char *s = std::getenv("GTI_SHALLOW_GRAPH_K_MULT"))
        mult = std::max(1u, (unsigned)std::strtoul(s, nullptr, 10));
    unsigned cap = 8192;
    if (const char *s = std::getenv("GTI_SHALLOW_GRAPH_SEARCH_K_CAP"))
        cap = std::max(L, (unsigned)std::strtoul(s, nullptr, 10));
    unsigned k = std::max(L, mult * L);
    k = std::min(k, cap);
    k = std::min(k, (unsigned)num_graph_vertices);
    return std::max(k, L);
}

unsigned shallowGraphSearchEf(unsigned graph_k, unsigned base_ef)
{
    unsigned ef = std::max(base_ef, std::max(200u, 2u * graph_k));
    if (const char *s = std::getenv("GTI_SHALLOW_GRAPH_EF_MIN"))
    {
        unsigned m = (unsigned)std::strtoul(s, nullptr, 10);
        if (m > 0)
            ef = std::max(ef, m);
    }
    return ef;
}

// n2 shallow graph: SearchByVectorM pool stores mixed routing/leaf entries; collect unique .nid (graph vertex)
// and re-rank all leaf oids under those vertices (n2 native descent only handles one level under routing node).
static void expandShallowGraphFromN2ResultPool(float *query, unsigned L, Objects *data,
                                               const std::vector<GTI_Entry *> &entries_sec,
                                               const std::unordered_set<unsigned> &lazy_deleted_oids,
                                               const std::vector<Neighbor> &n2_pool,
                                               std::vector<Neighbor> &out)
{
    std::unordered_set<unsigned> seen_gid;
    for (const Neighbor &nw : n2_pool)
    {
        if (nw.dis >= 1e20f)
            continue;
        unsigned gid = nw.nid;
        if (gid >= entries_sec.size() || entries_sec[gid] == nullptr)
            continue;
        seen_gid.insert(gid);
    }
    if (seen_gid.empty())
    {
        out.clear();
        return;
    }
    Distance distance;
    // oid -> (d_sq, graph_gid, leaf_entry_index) — deleteTree 依赖 Neighbor::oid 为叶槽位下标
    std::unordered_map<unsigned, std::tuple<float, unsigned, unsigned>> best;
    for (unsigned gid : seen_gid)
    {
        GTI_Entry *ent = entries_sec[gid];
        if (ent == nullptr)
            continue;
        std::vector<unsigned> oids;
        oids.reserve(512);
        if (ent->child == nullptr)
            oids.push_back((unsigned)ent->oid);
        else
            collectLeafOidsUnderNode(ent->child, oids);
        for (unsigned oid : oids)
        {
            if (lazy_deleted_oids.find(oid) != lazy_deleted_oids.end())
                continue;
            if (oid >= data->vecs.size() || data->vecs[oid].empty())
                continue;
            float d_eucl = distance.getDisP(data->vecs[oid].data(), query, data->type, data->dim);
            float d_sq = d_eucl * d_eucl;
            unsigned leid = 0;
            GTI_Node *leaf_tmp = nullptr;
            if (ent->child != nullptr)
                findLeafEidForOidInSubtree(ent->child, oid, leaf_tmp, leid);
            auto it = best.find(oid);
            if (it == best.end() || d_sq < std::get<0>(it->second))
                best[oid] = std::make_tuple(d_sq, gid, leid);
        }
    }
    out.clear();
    out.reserve(best.size());
    for (const auto &kv : best)
    {
        const auto &t = kv.second;
        out.push_back(Neighbor((int)kv.first, std::get<0>(t), std::get<1>(t), true, std::get<2>(t)));
    }
    std::sort(out.begin(), out.end(), [](const Neighbor &a, const Neighbor &b) { return a.dis < b.dis; });
    if (out.size() > L)
        out.resize(L);
}

} // namespace

void GTI::loadSplitConfigFromEnv()
{
    // Strategy (default: LB for backward compatibility)
    if (const char *s = std::getenv("GTI_SPLIT_STRATEGY"))
    {
        std::string v(s);
        for (auto &c : v)
            c = (char)std::tolower(c);
        if (v == "mst")
            split_strategy = SplitStrategy::MST;
        else
            split_strategy = SplitStrategy::LB;
    }
    // else: keep default LB

    auto read_int = [](const char *name, int &dst, int default_val) {
        if (const char *s = std::getenv(name))
            dst = std::atoi(s);
        else
            dst = default_val;
    };
    auto read_uint = [](const char *name, unsigned &dst, unsigned default_val) {
        if (const char *s = std::getenv(name))
            dst = (unsigned)std::strtoul(s, nullptr, 10);
        else
            dst = default_val;
    };
    auto read_float = [](const char *name, float &dst, float default_val) {
        if (const char *s = std::getenv(name))
            dst = (float)std::atof(s);
        else
            dst = default_val;
    };
    auto read_bool = [](const char *name, bool &dst, bool default_val) {
        if (const char *s = std::getenv(name))
        {
            int v = std::atoi(s);
            dst = (v != 0);
        }
        else
            dst = default_val;
    };

    // Use defaults from struct if env not set
    read_int("GTI_MST_FULL_THRESHOLD", mst_cfg.full_mst_threshold, mst_cfg.full_mst_threshold);
    read_int("GTI_MST_SAMPLE_SIZE", mst_cfg.sample_size, mst_cfg.sample_size);
    read_float("GTI_MST_BALANCE_MIN_FRAC", mst_cfg.balance_min_frac, mst_cfg.balance_min_frac);
    read_bool("GTI_MST_USE_SAMPLING", mst_cfg.use_sampling_if_large, mst_cfg.use_sampling_if_large);
    read_uint("GTI_MST_SEED", mst_cfg.seed, mst_cfg.seed);

    // Graph build level offset: 1 = leaf parent (default), 2 = grandparent, etc.
    if (const char *s = std::getenv("GTI_GRAPH_LEVEL_OFFSET"))
    {
        unsigned v = (unsigned)std::strtoul(s, nullptr, 10);
        if (v >= 1)
            graph_level_offset = v;
    }
}

void GTI::promote_mst(const std::vector<GTI_Entry *> &entries,
                      int &p1_idx,
                      int &p2_idx,
                      MSTSplitConfig const &cfg,
                      std::vector<float> *out_dists1,
                      std::vector<float> *out_dists2)
{
    const int m = (int)entries.size();
    p1_idx = 0;
    p2_idx = (m > 1) ? 1 : 0;
    if (m <= 1)
        return;

    // Use stack-allocated Distance to avoid allocation overhead
    Distance distance;

    // Step 1: pick working set indices: full or sampled (with smart sampling option)
    std::vector<int> work_idx;
    work_idx.reserve(m);

    const bool use_sampling = cfg.use_sampling_if_large && (m > cfg.full_mst_threshold);
    if (use_sampling)
    {
        const int s = std::min(cfg.sample_size, m);
        
        if (cfg.use_smart_sampling && s < m)
        {
            // Smart sampling: k-means++ style initialization
            // First, randomly sample half
            const int random_half = s / 2;
            std::vector<int> all(m);
            std::iota(all.begin(), all.end(), 0);
            std::mt19937 rng(cfg.seed);
            std::shuffle(all.begin(), all.end(), rng);
            work_idx.assign(all.begin(), all.begin() + random_half);
            
            // Then, sample the rest using farthest-first traversal
            std::vector<float> min_dists(m, std::numeric_limits<float>::infinity());
            for (int idx : work_idx)
            {
                const unsigned oid = entries[idx]->oid;
                for (int i = 0; i < m; i++)
                {
                    float d = distance.getDisP(data->vecs[oid].data(), data->vecs[entries[i]->oid].data(), data->type, data->dim);
                    if (d < min_dists[i])
                        min_dists[i] = d;
                }
            }
            
            // Add farthest points
            for (int added = random_half; added < s; added++)
            {
                int farthest = -1;
                float max_min_dist = -1.0f;
                for (int i = 0; i < m; i++)
                {
                    bool already_selected = false;
                    for (int idx : work_idx)
                    {
                        if (idx == i)
                        {
                            already_selected = true;
                            break;
                        }
                    }
                    if (!already_selected && min_dists[i] > max_min_dist)
                    {
                        max_min_dist = min_dists[i];
                        farthest = i;
                    }
                }
                if (farthest >= 0)
                {
                    work_idx.push_back(farthest);
                    const unsigned oid_far = entries[farthest]->oid;
                    for (int i = 0; i < m; i++)
                    {
                        float d = distance.getDisP(data->vecs[oid_far].data(), data->vecs[entries[i]->oid].data(), data->type, data->dim);
                        if (d < min_dists[i])
                            min_dists[i] = d;
                    }
                }
            }
        }
        else
        {
            // Random sampling
            std::vector<int> all(m);
            std::iota(all.begin(), all.end(), 0);
            std::mt19937 rng(cfg.seed);
            std::shuffle(all.begin(), all.end(), rng);
            work_idx.assign(all.begin(), all.begin() + s);
        }
    }
    else
    {
        work_idx.resize(m);
        std::iota(work_idx.begin(), work_idx.end(), 0);
    }

    const int s = (int)work_idx.size();
    if (s <= 1)
        return;

    auto dist_entry = [&](int a, int b) -> float {
        const unsigned oid_a = entries[work_idx[a]]->oid;
        const unsigned oid_b = entries[work_idx[b]]->oid;
        return distance.getDisP(data->vecs[oid_a].data(), data->vecs[oid_b].data(), data->type, data->dim);
    };

    // Step 2: Build MST on working set
    std::vector<float> D((size_t)s * (size_t)s, 0.0f);
    for (int i = 0; i < s; i++)
    {
        for (int j = i + 1; j < s; j++)
        {
            float d = dist_entry(i, j);
            D[(size_t)i * s + j] = d;
            D[(size_t)j * s + i] = d;
        }
    }

    // Prim MST on working set
    std::vector<float> key(s, std::numeric_limits<float>::infinity());
    std::vector<int> parent(s, -1);
    std::vector<char> in_mst(s, 0);
    key[0] = 0.0f;
    for (int it = 0; it < s; it++)
    {
        int u = -1;
        float best = std::numeric_limits<float>::infinity();
        for (int i = 0; i < s; i++)
        {
            if (!in_mst[i] && key[i] < best)
            {
                best = key[i];
                u = i;
            }
        }
        if (u == -1)
            break;
        in_mst[u] = 1;
        for (int v = 0; v < s; v++)
        {
            if (!in_mst[v])
            {
                float w = D[(size_t)u * s + v];
                if (w < key[v])
                {
                    key[v] = w;
                    parent[v] = u;
                }
            }
        }
    }

    // Step 3: Find candidate cut edges (top-k longest edges)
    struct Edge {
        int u, v;
        float w;
    };
    std::vector<Edge> edges;
    edges.reserve(s - 1);
    for (int v = 1; v < s; v++)
    {
        int u = parent[v];
        if (u < 0)
            continue;
        float w = D[(size_t)v * s + u];
        edges.push_back({v, u, w});
    }
    
    if (edges.empty())
    {
        // No valid edges, fallback
        return;
    }
    
    // Sort edges by weight (descending)
    std::sort(edges.begin(), edges.end(), [](const Edge &a, const Edge &b) {
        return a.w > b.w;
    });
    
    const int num_candidates = std::min(cfg.cut_edge_candidates, (int)edges.size());
    
    // Helper function to get components after cutting an edge
    auto get_components_after_cut = [&](int cut_a, int cut_b) -> std::pair<std::vector<int>, std::vector<int>> {
        std::vector<std::vector<int>> adj(s);
        for (int v = 1; v < s; v++)
        {
            int u = parent[v];
            if (u < 0)
                continue;
            if ((v == cut_a && u == cut_b) || (v == cut_b && u == cut_a))
                continue;
            adj[v].push_back(u);
            adj[u].push_back(v);
        }
        
        std::vector<int> comp(s, -1);
        std::vector<int> stack;
        comp[cut_a] = 0;
        stack.push_back(cut_a);
        while (!stack.empty())
        {
            int u = stack.back();
            stack.pop_back();
            for (int v : adj[u])
            {
                if (comp[v] == -1)
                {
                    comp[v] = 0;
                    stack.push_back(v);
                }
            }
        }
        for (int i = 0; i < s; i++)
            if (comp[i] == -1)
                comp[i] = 1;
        
        std::vector<int> g1, g2;
        for (int i = 0; i < s; i++)
        {
            if (comp[i] == 0)
                g1.push_back(i);
            else
                g2.push_back(i);
        }
        return {g1, g2};
    };
    
    // Helper function to compute overlap metric
    auto compute_overlap_metric = [&](const std::vector<int> &g1_sample, const std::vector<int> &g2_sample,
                                       int m1_idx, int m2_idx) -> float {
        if (g1_sample.empty() || g2_sample.empty())
            return 1e10f; // Bad split
        
        // Compute max distances within each group
        float max_dist1 = 0.0f, max_dist2 = 0.0f;
        for (int idx : g1_sample)
        {
            float d = D[(size_t)m1_idx * s + idx];
            if (d > max_dist1)
                max_dist1 = d;
        }
        for (int idx : g2_sample)
        {
            float d = D[(size_t)m2_idx * s + idx];
            if (d > max_dist2)
                max_dist2 = d;
        }
        
        // Distance between medoids
        float dist_medoids = D[(size_t)m1_idx * s + m2_idx];
        if (dist_medoids < 1e-6f)
            return 1e10f; // Medoids too close
        
        // Overlap metric: (max_dist1 + max_dist2) / dist_medoids
        return (max_dist1 + max_dist2) / dist_medoids;
    };
    
    // Try each candidate cut edge and select the best one
    int best_cut_a = edges[0].u, best_cut_b = edges[0].v;
    float best_overlap = 1e10f;
    
    for (int cand = 0; cand < num_candidates; cand++)
    {
        int cut_a = edges[cand].u;
        int cut_b = edges[cand].v;
        
        std::pair<std::vector<int>, std::vector<int>> comps = get_components_after_cut(cut_a, cut_b);
        std::vector<int> &g1_sample = comps.first;
        std::vector<int> &g2_sample = comps.second;
        
        if (g1_sample.empty() || g2_sample.empty())
            continue;
        
        // Compute sample medoids
        auto medoid_of_sample = [&](const std::vector<int> &g) -> int {
            double best_sum = 1e100;
            int best_i = g[0];
            for (int ii : g)
            {
                double sum = 0.0;
                for (int jj : g)
                    sum += D[(size_t)ii * s + jj];
                if (sum < best_sum)
                {
                    best_sum = sum;
                    best_i = ii;
                }
            }
            return best_i;
        };
        
        int m1_sample = medoid_of_sample(g1_sample);
        int m2_sample = medoid_of_sample(g2_sample);
        
        float overlap = compute_overlap_metric(g1_sample, g2_sample, m1_sample, m2_sample);
        
        if (overlap < best_overlap)
        {
            best_overlap = overlap;
            best_cut_a = cut_a;
            best_cut_b = cut_b;
        }
    }
    
    // Use the best cut edge
    std::pair<std::vector<int>, std::vector<int>> best_comps = get_components_after_cut(best_cut_a, best_cut_b);
    std::vector<int> &g1_sample = best_comps.first;
    std::vector<int> &g2_sample = best_comps.second;
    
    if (g1_sample.empty() || g2_sample.empty())
    {
        return; // Fallback
    }
    
    // Get sample-medoids
    auto medoid_of_sample = [&](const std::vector<int> &g) -> int {
        double best_sum = 1e100;
        int best_i = g[0];
        for (int ii : g)
        {
            double sum = 0.0;
            for (int jj : g)
                sum += D[(size_t)ii * s + jj];
            if (sum < best_sum)
            {
                best_sum = sum;
                best_i = ii;
            }
        }
        return best_i;
    };
    
    int m1_sample = medoid_of_sample(g1_sample);
    int m2_sample = medoid_of_sample(g2_sample);
    int r1_s_idx = work_idx[m1_sample];
    int r2_s_idx = work_idx[m2_sample];

    // Step 4: Assign ALL m entries to C1/C2 using r1_s/r2_s
    std::vector<float> d1_all(m), d2_all(m);
    const unsigned oid_r1 = entries[r1_s_idx]->oid;
    const unsigned oid_r2 = entries[r2_s_idx]->oid;
    for (int i = 0; i < m; i++)
    {
        const unsigned oid = entries[i]->oid;
        d1_all[i] = distance.getDisP(data->vecs[oid_r1].data(), data->vecs[oid].data(), data->type, data->dim);
        d2_all[i] = distance.getDisP(data->vecs[oid_r2].data(), data->vecs[oid].data(), data->type, data->dim);
    }

    std::vector<int> C1, C2;
    C1.reserve(m);
    C2.reserve(m);
    for (int i = 0; i < m; i++)
    {
        if (d1_all[i] < d2_all[i])
            C1.push_back(i);
        else
            C2.push_back(i);
    }

    // Step 5: Improved medoid refine with two-stage refinement and overlap minimization
    const int MEDOID_EXACT_THRESHOLD = 128;
    
    auto medoid_refine_full = [&](const std::vector<int> &group, int other_medoid_idx) -> int {
        const int g_size = (int)group.size();
        if (g_size == 0)
            return -1; // Return invalid index to signal error

        // Adaptive candidate count
        int candidate_k = cfg.medoid_candidate_k;
        if (cfg.use_adaptive_params)
        {
            candidate_k = std::min(64 + g_size / 10, 256);
        }

        if (g_size <= MEDOID_EXACT_THRESHOLD)
        {
            // Exact medoid: O(g_size^2)
            double best_score = 1e100;
            int best_i = group[0];
            
            for (int ii : group)
            {
                double sum = 0.0;
                const unsigned oid_ii = entries[ii]->oid;
                for (int jj : group)
                {
                    const unsigned oid_jj = entries[jj]->oid;
                    sum += distance.getDisP(data->vecs[oid_ii].data(), data->vecs[oid_jj].data(), data->type, data->dim);
                }
                
                double score = sum;
                
                // Add overlap penalty if enabled
                if (cfg.use_overlap_minimization && other_medoid_idx >= 0)
                {
                    const unsigned oid_other = entries[other_medoid_idx]->oid;
                    float dist_to_other = distance.getDisP(data->vecs[oid_ii].data(), data->vecs[oid_other].data(), data->type, data->dim);
                    // Penalize if medoids are too close
                    if (dist_to_other < 1e-6f)
                        score += 1e10;
                    else
                        score += sum / dist_to_other; // Overlap penalty
                }
                
                if (score < best_score)
                {
                    best_score = score;
                    best_i = ii;
                }
            }
            return best_i;
        }
        else
        {
            // Two-stage refinement if enabled
            if (cfg.use_two_stage_refine)
            {
                // Stage 1: Sample more candidates
                const int stage1_k = std::min(candidate_k * 2, g_size); // Sample 2x candidates
                std::vector<int> stage1_candidates(stage1_k);
                std::mt19937 rng(cfg.seed + 1);
                std::uniform_int_distribution<int> dist(0, g_size - 1);
                for (int i = 0; i < stage1_k; i++)
                    stage1_candidates[i] = group[dist(rng)];

                // Compute approximate scores for stage 1 candidates
                std::vector<std::pair<double, int>> stage1_scores;
                for (int cand : stage1_candidates)
                {
                    double sum = 0.0;
                    const unsigned oid_cand = entries[cand]->oid;
                    // Sample a subset for fast evaluation
                    const int eval_size = std::min(64, g_size);
                    std::vector<int> eval_indices(eval_size);
                    std::iota(eval_indices.begin(), eval_indices.end(), 0);
                    std::shuffle(eval_indices.begin(), eval_indices.end(), rng);
                    
                    for (int i = 0; i < eval_size; i++)
                    {
                        int jj = group[eval_indices[i]];
                        const unsigned oid_jj = entries[jj]->oid;
                        sum += distance.getDisP(data->vecs[oid_cand].data(), data->vecs[oid_jj].data(), data->type, data->dim);
                    }
                    sum = sum * g_size / eval_size; // Scale up
                    stage1_scores.push_back({sum, cand});
                }
                
                // Select top candidates for stage 2
                std::sort(stage1_scores.begin(), stage1_scores.end());
                const int stage2_k = std::min(10, (int)stage1_scores.size());
                
                // Stage 2: Exact evaluation on top candidates
                double best_score = 1e100;
                int best_i = stage1_scores[0].second;
                
                for (int i = 0; i < stage2_k; i++)
                {
                    int cand = stage1_scores[i].second;
                    double sum = 0.0;
                    const unsigned oid_cand = entries[cand]->oid;
                    for (int jj : group)
                    {
                        const unsigned oid_jj = entries[jj]->oid;
                        sum += distance.getDisP(data->vecs[oid_cand].data(), data->vecs[oid_jj].data(), data->type, data->dim);
                    }
                    
                    double score = sum;
                    
                    // Add overlap penalty if enabled
                    if (cfg.use_overlap_minimization && other_medoid_idx >= 0)
                    {
                        const unsigned oid_other = entries[other_medoid_idx]->oid;
                        float dist_to_other = distance.getDisP(data->vecs[oid_cand].data(), data->vecs[oid_other].data(), data->type, data->dim);
                        if (dist_to_other < 1e-6f)
                            score += 1e10;
                        else
                            score += sum / dist_to_other;
                    }
                    
                    if (score < best_score)
                    {
                        best_score = score;
                        best_i = cand;
                    }
                }
                return best_i;
            }
            else
            {
                // Single-stage: sample candidates and evaluate
                const int k = std::min(candidate_k, g_size);
                std::vector<int> candidates(k);
                std::mt19937 rng(cfg.seed + 1);
                std::uniform_int_distribution<int> dist(0, g_size - 1);
                for (int i = 0; i < k; i++)
                    candidates[i] = group[dist(rng)];

                double best_score = 1e100;
                int best_i = candidates[0];
                for (int cand : candidates)
                {
                    double sum = 0.0;
                    const unsigned oid_cand = entries[cand]->oid;
                    for (int jj : group)
                    {
                        const unsigned oid_jj = entries[jj]->oid;
                        sum += distance.getDisP(data->vecs[oid_cand].data(), data->vecs[oid_jj].data(), data->type, data->dim);
                    }
                    
                    double score = sum;
                    
                    // Add overlap penalty if enabled
                    if (cfg.use_overlap_minimization && other_medoid_idx >= 0)
                    {
                        const unsigned oid_other = entries[other_medoid_idx]->oid;
                        float dist_to_other = distance.getDisP(data->vecs[oid_cand].data(), data->vecs[oid_other].data(), data->type, data->dim);
                        if (dist_to_other < 1e-6f)
                            score += 1e10;
                        else
                            score += sum / dist_to_other;
                    }
                    
                    if (score < best_score)
                    {
                        best_score = score;
                        best_i = cand;
                    }
                }
                return best_i;
            }
        }
    };

    // Iterative refine if enabled
    int iter = 0;
    while (iter < cfg.max_iterations)
    {
        // Refine medoids (pass other medoid index for overlap minimization)
        int new_p1 = medoid_refine_full(C1, iter > 0 ? p2_idx : -1);
        int new_p2 = medoid_refine_full(C2, new_p1);
        
        // Check if medoid refine failed (returned -1)
        if (new_p1 < 0 || new_p2 < 0 || new_p1 >= m || new_p2 >= m)
        {
            // Fallback: use initial medoids
            break;
        }
        
        // Check convergence
        if (iter > 0 && new_p1 == p1_idx && new_p2 == p2_idx)
            break;
        
        p1_idx = new_p1;
        p2_idx = new_p2;
        
        // Reassign points based on new medoids
        if (iter < cfg.max_iterations - 1)
        {
            const unsigned oid1 = entries[p1_idx]->oid;
            const unsigned oid2 = entries[p2_idx]->oid;
            C1.clear();
            C2.clear();
            for (int i = 0; i < m; i++)
            {
                const unsigned oid = entries[i]->oid;
                float d1 = distance.getDisP(data->vecs[oid1].data(), data->vecs[oid].data(), data->type, data->dim);
                float d2 = distance.getDisP(data->vecs[oid2].data(), data->vecs[oid].data(), data->type, data->dim);
                if (d1 < d2)
                    C1.push_back(i);
                else
                    C2.push_back(i);
            }
        }
        
        iter++;
    }
    
    // Final validation: ensure p1_idx and p2_idx are valid
    if (p1_idx < 0 || p2_idx < 0 || p1_idx >= m || p2_idx >= m || p1_idx == p2_idx)
    {
        // Fallback to initial assignment
        p1_idx = 0;
        p2_idx = (m > 1) ? 1 : 0;
    }

    // Step 6: Precompute distances to refined p1/p2 for all entries (if requested)
    if (out_dists1 || out_dists2)
    {
        std::vector<float> &d1 = out_dists1 ? *out_dists1 : *out_dists2;
        std::vector<float> &d2 = out_dists2 ? *out_dists2 : d1;
        d1.resize(m);
        d2.resize(m);
        const unsigned oid1 = entries[p1_idx]->oid;
        const unsigned oid2 = entries[p2_idx]->oid;
        for (int i = 0; i < m; i++)
        {
            const unsigned oid = entries[i]->oid;
            d1[i] = distance.getDisP(data->vecs[oid1].data(), data->vecs[oid].data(), data->type, data->dim);
            d2[i] = distance.getDisP(data->vecs[oid2].data(), data->vecs[oid].data(), data->type, data->dim);
        }
    }
}

// Comparison function for two entries with dis_p
bool compareEnDisp(GTI_Entry *e1, GTI_Entry *e2)
{
    return e1->dis_p < e2->dis_p;
}

// Comparison function for two entries with dis_p + radius
bool compareEnDispR(GTI_Entry *e1, GTI_Entry *e2)
{
    return (e1->dis_p + e1->radius) < (e2->dis_p + e2->radius);
}

// Build GTI
void GTI::buildGTI(unsigned capacity_up_i, unsigned capacity_up_l, int m, Objects *data)
{
    init(capacity_up_i, capacity_up_l, m, data); // Initialize GTI
    
    // Print MST_CONFIG after loading from env (in init -> loadSplitConfigFromEnv)
    if (split_strategy == SplitStrategy::MST)
    {
        std::cout << "MST_CONFIG: full_threshold=" << mst_cfg.full_mst_threshold
                  << " sample_size=" << mst_cfg.sample_size
                  << " balance_min_frac=" << std::fixed << std::setprecision(6) << mst_cfg.balance_min_frac
                  << " use_sampling=" << (mst_cfg.use_sampling_if_large ? 1 : 0)
                  << " seed=" << mst_cfg.seed
                  << " medoid_k=" << mst_cfg.medoid_candidate_k << std::endl;
    }
    
    insertAll();                                 // Insert all objects to tree

    if (graph_level_offset != 1)
        std::cout << "[GTI] graph_level_offset=" << graph_level_offset
                  << " (build graph at height-" << (1 + graph_level_offset) << ")" << std::endl;

    buildGraphSec();                             // Build graph at configured level

    // Print MST statistics if using MST strategy
    if (split_strategy == SplitStrategy::MST)
    {
        std::cout << "MST attempts: " << mst_attempts 
                  << ", used: " << mst_used 
                  << ", fallbacks: " << mst_fallback_count << std::endl;
    }
}

// Initialize GTI
void GTI::init(unsigned capacity_up_i, unsigned capacity_up_l, int m, Objects *data)
{
    this->data = data; // Initialize data

    // Initialize node capacity
    this->capacity_up_i = capacity_up_i;
    this->capacity_up_l = capacity_up_l;

    // Initialize root node
    root = new GTI_Node();
    root->entries.resize(0);
    root->parent_node = NULL;
    root->type = 1; // Initially, the root node is a leaf node
    root->level = 0;

    height = 1; // Initialize tree height

    // Initialize graph parameters
    this->m = m;
    int core_count = std::thread::hardware_concurrency(); // Get number of cores
    n_threads = core_count / 2;                           // Number of threads
    max_m0 = 2 * m;
    ef_construction = 5 * max_m0;

    // Load split strategy/config from environment once per build
    loadSplitConfigFromEnv();
}

// Find parent node
GTI_Node *GTI::findParentNode(GTI_Node *N, GTI_Node *node)
{
    if (N == NULL || node == NULL)
        return NULL;

    if (N->type == 1)
        return NULL;

    for (unsigned i = 0; i < N->entries.size(); i++)
    {
        GTI_Node *child = N->entries[i]->child;
        if (child == node)
        {
            return N;
        }
        else
        {
            GTI_Node *parent = findParentNode(child, node);
            if (parent != NULL)
            {
                return parent;
            }
        }
    }

    return NULL;
}

// Find parent entry
int GTI::findParentEntry(GTI_Node *parent, GTI_Node *node)
{
    if (parent == NULL || node == NULL)
        return -1;

    for (unsigned i = 0; i < parent->entries.size(); i++)
    {
        if (parent->entries[i]->child == node)
            return i;
    }

    return -1;
}

// Find entry id in the node
int GTI::findEntry(GTI_Node *node, unsigned oid)
{
    if (node == NULL)
        return -1;

    for (unsigned i = 0; i < node->entries.size(); i++)
    {
        if (node->entries[i] != nullptr)
            if (node->entries[i]->oid == oid)
                return i;
    }

    return -1;
}

// Insert all objects to tree
void GTI::insertAll()
{
    std::vector<float> dists;         // Distances to routing objects
    std::vector<unsigned> entries_in; // 0, distance calculated and pruned; 1, distance calculated and not pruned (entries without radius enlargement);
                                      // 2, parent pruning

    // Insert all objects
    system("setterm -cursor on");
    for (unsigned i = 0; i < data->num; i++)
    {
        // Create leaf entry
        GTI_Entry *entry = new GTI_Entry();
        entry->oid = (int)i;
        entry->dis_p = INF_DIS;
        entry->radius = INF_DIS;
        entry->child = NULL;

        // Print progress bar
        // if (i < data->num - 1)
        // {
        //     printf("\rBUilding[%.2lf%%]:", i * 100.0 / (data->num - 1));
        // }
        // else
        // {
        //     printf("\rDone[%.2lf%%]:", i * 100.0 / (data->num - 1));
        // }
        // int show_num = i * 20 / data->num;
        // for (int j = 1; j <= show_num; j++)
        // {
        //     std::cout << "█";
        // }

        insert(root, entry, entries_in, dists, INF_DIS); // Insert objects
    }
    // std::cout << std::endl;
    // system("setterm -cursor on");

    std::vector<unsigned>().swap(entries_in);
    std::vector<float>().swap(dists);
}

// Insert objects
void GTI::insert(GTI_Node *node, GTI_Entry *entry, std::vector<unsigned> &entries_in, std::vector<float> &dists, float dis_p2o)
{
    if (node->type == 0) // Current node is an internal node
    {
        std::vector<unsigned>().swap(entries_in);
        std::vector<float>().swap(dists);
        entries_in.insert(entries_in.end(), node->entries.size(), 0);
        dists.resize(node->entries.size());

        bool is_entries_in = false; // false, no entry without radius enlargement
                                    // true, entries without radius enlargement
        float min_dis = INF_DIS;    // Min distance
        int min_id = 0;             // Entry ID corresponding to the min distance

        Distance distance; // Use stack allocation to avoid overhead

        // Determination of entries_in
        for (unsigned i = 0; i < node->entries.size(); i++)
        {
            // Parent is not NULL
            if (node->parent_node != NULL)
            {
                // Use parent for pruning
                float dis = abs(dis_p2o - node->entries[i]->dis_p);
                if (dis > node->entries[i]->radius)
                {
                    entries_in[i] = 2; // The radius of the entry is increased
                }
            }

            // Not pruned by the parent
            if (entries_in[i] != 2)
            {
                float dis = distance.getDisP(data->vecs[node->entries[i]->oid].data(), data->vecs[entry->oid].data(),
                                              data->type, data->dim); // Calculate distance

                if (dis <= node->entries[i]->radius) // Distance calculated and not pruned (entries without radius enlargement)
                {
                    entries_in[i] = 1;
                    is_entries_in = true;

                    // Find the min distance
                    if (dis < min_dis)
                    {
                        min_dis = dis;
                        min_id = i;
                    }
                }
                dists[i] = dis;
            }
        }

        // No entry without radius enlargement
        if (!is_entries_in)
        {
            min_dis = INF_DIS;

            // Find the min distance (min radius increases)
            for (unsigned i = 0; i < node->entries.size(); i++)
            {
                if (entries_in[i] == 2)
                {
                    float dis = distance.getDisP(data->vecs[node->entries[i]->oid].data(), data->vecs[entry->oid].data(),
                                                  data->type, data->dim); // Calculate distance
                    dists[i] = dis;
                }

                // Find the min distance (min radius increases)
                if (dists[i] - node->entries[i]->radius < min_dis)
                {
                    min_dis = dists[i] - node->entries[i]->radius;
                    min_id = i;
                }
            }

            node->entries[min_id]->radius = dists[min_id]; // Update radius
        }

        insert(node->entries[min_id]->child, entry, entries_in, dists, dists[min_id]); // Recursive insertion
    }
    else // Current node is a leaf node
    {
        if (node->entries.size() < capacity_up_l) // Node is not full
        {
            // Record distance from parent
            if (node->parent_node != NULL)
            {
                entry->dis_p = dis_p2o;
            }

            node->entries.push_back(entry); // Store the enrty in leaf node
        }
        else // Node is full
        {
            auto s = std::chrono::high_resolution_clock::now();
            split(node, entry); // Split node
            auto e = std::chrono::high_resolution_clock::now();
            std::chrono::duration<float> diff = e - s;
            time_split += diff.count();
        }
    }
}

// Split node
void GTI::split(GTI_Node *node, GTI_Entry *entry)
{
    GTI_Node *node2 = new GTI_Node();
    GTI_Entry *entry1 = new GTI_Entry();
    GTI_Entry *entry2 = new GTI_Entry();
    std::vector<GTI_Entry *> entries;
    int min_oid[2]; // The index of the selected entry
    auto s = std::chrono::high_resolution_clock::now();
    GTI_Node *parent_node = node->parent_node; // Parent node
    auto e = std::chrono::high_resolution_clock::now();
    std::chrono::duration<float> diff = e - s;
    std::vector<float> dists_split;

    // Initialize split information
    for (unsigned i = 0; i < node->entries.size(); i++)
    {
        entries.push_back(node->entries[i]);
    }
    entries.push_back(entry);
    node2->type = node->type;
    node2->level = node->level;
    entry1->child = node;
    entry2->child = node2;

    // Promote and partition (baseline vs MST-split)
    // Only use MST on leaf nodes (node->type == 1) to avoid expensive computation on internal nodes
    if (split_strategy == SplitStrategy::MST && node->type == 1)
    {
        mst_attempts++; // Count MST attempt
        int p1_idx = 0, p2_idx = 0;
        std::vector<float> d1, d2;
        promote_mst(entries, p1_idx, p2_idx, mst_cfg, &d1, &d2);

        // Check if promote_mst successfully initialized d1 and d2
        // If not (e.g., early return due to small size or empty groups), fallback to baseline
        if (d1.size() != entries.size() || d2.size() != entries.size() || 
            p1_idx < 0 || p2_idx < 0 || p1_idx >= (int)entries.size() || p2_idx >= (int)entries.size() ||
            p1_idx == p2_idx)
        {
            // fallback/baseline - promote_mst failed or returned invalid results
            mst_fallback_count++;
            promoteLb(entries, min_oid, parent_node, node, dists_split);
        }
        else
        {
            // Build dists_split layout expected by partitionGh
            dists_split.resize(2 * entries.size());
            for (size_t i = 0; i < entries.size(); i++)
            {
                dists_split[i] = d1[i];
                dists_split[entries.size() + i] = d2[i];
            }

            // Balance check: if too imbalanced, fallback to original promoteLb
            size_t c1 = 0, c2 = 0;
            for (size_t i = 0; i < entries.size(); i++)
            {
                if (dists_split[i] < dists_split[entries.size() + i])
                    c1++;
                else
                    c2++;
            }
            const float min_frac = mst_cfg.balance_min_frac;
            const size_t min_allowed = (size_t)std::ceil(min_frac * (float)entries.size());
            if (std::min(c1, c2) < min_allowed)
            {
                // fallback/baseline - too imbalanced
                mst_fallback_count++;
                promoteLb(entries, min_oid, parent_node, node, dists_split);
            }
            else
            {
                mst_used++; // MST successfully used
                min_oid[0] = (int)entries[p1_idx]->oid;
                min_oid[1] = (int)entries[p2_idx]->oid;
            }
        }
    }
    else
    {
        promoteLb(entries, min_oid, parent_node, node, dists_split);
    }
    partitionGh(entries, node, node2, entry1, entry2, min_oid[0], min_oid[1], dists_split); // Divide the entries into two nodes using generalized hyperplane

    // Release memory
    std::vector<GTI_Entry *>().swap(entries);
    std::vector<float>().swap(dists_split);

    if (parent_node == NULL) // Current node is root node, allocate a new root node
    {
        // Allocate a new root node
        height++;
        GTI_Node *new_root = new GTI_Node();
        new_root->type = 0;
        new_root->parent_node = NULL;
        new_root->level = height;

        // Update information
        entry1->dis_p = INF_DIS;
        entry2->dis_p = INF_DIS;
        new_root->entries.push_back(entry1);
        new_root->entries.push_back(entry2);
        node->parent_node = new_root;
        node2->parent_node = new_root;
        root = new_root;
    }
    else // Current node is not root node
    {
        float dist = INF_DIS;
        GTI_Node *grand_node = parent_node->parent_node;          // Grand node
        int parent_entry_id = findParentEntry(parent_node, node); // Parent entry id

        // Calculate the distance to new entry1's parent
        if (grand_node != NULL)
        {
            int grand_entry_id = findParentEntry(grand_node, parent_node); // Grandpa entry id
            Distance distance;
            int rid = grand_node->entries[grand_entry_id]->oid;
            dist = distance.getDisP(data->vecs[entry1->oid].data(), data->vecs[rid].data(), data->type, data->dim);
        }
        entry1->dis_p = dist;

        // Replace old parent entry with new entry1
        delete parent_node->entries[parent_entry_id];
        parent_node->entries[parent_entry_id] = NULL;
        parent_node->entries[parent_entry_id] = entry1;

        if (parent_node->entries.size() < capacity_up_i) // Parent node is not full, store entry2
        {
            // Calculate the distance to new entry's parent
            float dist = INF_DIS;
            if (grand_node != NULL)
            {
                int grand_entry_id = findParentEntry(grand_node, parent_node); // Grandpa entry id
                Distance distance;
                int rid = grand_node->entries[grand_entry_id]->oid;
                dist = distance.getDisP(data->vecs[entry2->oid].data(), data->vecs[rid].data(), data->type, data->dim);
            }
            entry2->dis_p = dist;

            // Store entry2 in parent node
            parent_node->entries.push_back(entry2);
            node2->parent_node = parent_node;
        }
        else // Parent node is full, split nodes recursively
        {
            split(parent_node, entry2); // Split nodes recursively
        }
    }
}

// M_LB_DIST1 methods to choose two new routing objects
void GTI::promoteLb(std::vector<GTI_Entry *> &entries, int *min_oid, GTI_Node *parent_node, GTI_Node *node, std::vector<float> &dists_split)
{
    dists_split.resize(2 * entries.size()); // Distance between any pair
    Distance distance; // Use stack allocation
    int oid1 = 0;
    int oid2 = 0;

    if (parent_node != NULL) // Parent node is not null
    {
        // Confirm parent entry's routing object as the first routing object
        int parent_entry_id = findParentEntry(parent_node, node);
        oid1 = parent_node->entries[parent_entry_id]->oid;

        // Get the distance between the new entry and the first routing object
        for (unsigned i = 0; i < entries.size(); i++)
        {
            if (i < entries.size() - 1)
            {
                dists_split[i] = entries[i]->dis_p;
            }
            else
            {
                int oid = entries[i]->oid;
                float dist = distance.getDisP(data->vecs[oid1].data(), data->vecs[oid].data(),
                                               data->type, data->dim);
                dists_split[i] = dist;
            }
        }
    }
    else // Parent node is null
    {
        oid1 = entries[entries.size() - 2]->oid; // Confirm the first entry's routing objrct as the first routing object

        // Calculates the distances between all entries and the first routing object
        // #pragma omp parallel num_threads(48)
        for (unsigned i = 0; i < entries.size(); i++)
        {
            int oid = entries[i]->oid;
            float dist = distance.getDisP(data->vecs[oid1].data(), data->vecs[oid].data(),
                                           data->type, data->dim);
            dists_split[i] = dist;
        }
    }

    // Find the farthest entry from the first routing object as the second routing object
    auto max_it_entry = std::max_element(dists_split.begin(), dists_split.begin() + entries.size());
    int max_index_entry = std::distance(dists_split.begin(), max_it_entry);
    oid2 = entries[max_index_entry]->oid;

    // Store two routing objects
    min_oid[0] = oid1;
    min_oid[1] = oid2;

    // if (oid1 == oid2)
    //     printf("equal!!!\n");

    // Calculates the distances between all entries and the first routing object
    // #pragma omp parallel num_threads(48)
    for (unsigned i = 0; i < entries.size(); i++)
    {
        int oid = entries[i]->oid;
        float dist = distance.getDisP(data->vecs[oid2].data(), data->vecs[oid].data(),
                                       data->type, data->dim);
        dists_split[entries.size() + i] = dist;
    }
}

// Divide the entries into two nodes using generalized hyperplane
void GTI::partitionGh(std::vector<GTI_Entry *> &entries, GTI_Node *node1, GTI_Node *node2, GTI_Entry *entry1,
                      GTI_Entry *entry2, int oid1, int oid2, std::vector<float> dists_split)
{
    std::vector<int> node1_idx; // Original index of entry in node1
    std::vector<int> node2_idx; // Original index of entry in node2
    // std::vector<GTI_Entry *>().swap(node1->entries);
    // std::vector<GTI_Entry *>().swap(node2->entries);
    node1->entries.clear();
    node2->entries.clear();

    // Divide the entries into two nodes using generalized hyperplane partition
    for (unsigned i = 0; i < entries.size(); i++)
    {
        if (dists_split[i] < dists_split[entries.size() + i]) // Assigned to node1
        {
            entries[i]->dis_p = dists_split[i];
            node1->entries.push_back(entries[i]);
            node1_idx.push_back(i);
            if (entries[i]->child != NULL)
            {
                entries[i]->child->parent_node = node1;
            }
        }
        else // Assigned to node2
        {
            entries[i]->dis_p = dists_split[entries.size() + i];
            node2->entries.push_back(entries[i]);
            node2_idx.push_back(i);
            if (entries[i]->child != NULL)
                entries[i]->child->parent_node = node2;
        }
    }

    // Update radius of promote entries
    if (entries[0]->child == NULL) // Split leaf node
    {
        auto max_it_entry1 = std::max_element(node1->entries.begin(), node1->entries.end(), compareEnDisp);
        auto max_it_entry2 = std::max_element(node2->entries.begin(), node2->entries.end(), compareEnDisp);
        int max_index_entry1 = std::distance(node1->entries.begin(), max_it_entry1);
        int max_index_entry2 = std::distance(node2->entries.begin(), max_it_entry2);
        entry1->radius = node1->entries[max_index_entry1]->dis_p;
        entry2->radius = node2->entries[max_index_entry2]->dis_p;
    }
    else // Split internal node
    {
        auto max_it_entry1 = std::max_element(node1->entries.begin(), node1->entries.end(), compareEnDispR);
        auto max_it_entry2 = std::max_element(node2->entries.begin(), node2->entries.end(), compareEnDispR);
        int max_index_entry1 = std::distance(node1->entries.begin(), max_it_entry1);
        int max_index_entry2 = std::distance(node2->entries.begin(), max_it_entry2);
        entry1->radius = node1->entries[max_index_entry1]->dis_p + node1->entries[max_index_entry1]->radius;
        entry2->radius = node2->entries[max_index_entry2]->dis_p + node2->entries[max_index_entry2]->radius;
    }

    std::sort(node1->entries.begin(), node1->entries.end(), compareEnDisp);
    std::sort(node2->entries.begin(), node2->entries.end(), compareEnDisp);

    // Update other information of promote entries
    entry1->oid = oid1;
    entry2->oid = oid2;

    // Release memory
    std::vector<int>().swap(node1_idx);
    std::vector<int>().swap(node2_idx);
}

// Build graph at second level
void GTI::buildGraphSec()
{
    std::vector<GTI_Node *> nodes;
    nodes.push_back(root);
    map.resize(data->num);
    std::fill(map.begin(), map.end(), -1);

    // Build graph at configured level (graph_level_offset from leaves).
    // Default graph_level_offset=1 keeps the original behavior: build on leaf parent.
    const unsigned graph_stop = (height > graph_level_offset) ? (height - graph_level_offset) : 1u;
    unsigned size = nodes.size();
    for (unsigned i = 0; i < graph_stop; i++)
    {
        for (unsigned j = 0; j < size; ++j)
        {
            if (i < graph_stop - 1) // Upper level: keep traversing
            {
                for (unsigned k = 0; k < nodes[j]->entries.size(); k++)
                {
                    nodes.push_back(nodes[j]->entries[k]->child);
                }
            }
            else // Graph build level: collect entries
            {
                for (unsigned k = 0; k < nodes[j]->entries.size(); k++)
                {
                    entries_sec.push_back(nodes[j]->entries[k]);
                    unsigned oid = nodes[j]->entries[k]->oid;
                    map[oid] = entries_sec.size() - 1;
                }
            }
        }
        nodes.erase(nodes.begin(), nodes.begin() + size);
        size = nodes.size();
    }

    // Build graph at second level
#ifdef GTI_USE_WOLVERINE
    unsigned ef_build = ef_construction;
    if (const char *s = std::getenv("GTI_WOLVERINE_EF_BUILD"))
        ef_build = (unsigned)std::strtoul(s, nullptr, 10);
    wolverine_space = new hnswlib::L2Space(data->dim);
    index_wolverine = new hnswlib::HierarchicalNSW<float>(wolverine_space, entries_sec.size() + 10000, m, ef_build, 100);
    for (unsigned i = 0; i < entries_sec.size(); i++)
    {
        unsigned oid = entries_sec[i]->oid;
        index_wolverine->addPoint(data->vecs[oid].data(), (hnswlib::labeltype)i);
    }
#elif defined(GTI_USE_SHG)
    unsigned ef_build = ef_construction;
    if (const char *s = std::getenv("GTI_SHG_EF_BUILD"))
        ef_build = (unsigned)std::strtoul(s, nullptr, 10);
    heds_space = new hnswlib::L2Space(data->dim);
    size_t max_el = (size_t)entries_sec.size() + 10000;
    bool use_full_dim_level_skip = false;
    if (const char *s = std::getenv("GTI_SHG_FULL_DIM_LEVEL_SKIP"))
        use_full_dim_level_skip = (std::strcmp(s, "1") == 0 || std::strcmp(s, "true") == 0);
    if (use_full_dim_level_skip)
        std::cout << "[SHG] GTI_SHG_FULL_DIM_LEVEL_SKIP=1: level-skipping uses full-dimensional distance (no compression)" << std::endl;
    unsigned shg_m = m;
    if (const char *s = std::getenv("GTI_SHG_M"))
        shg_m = std::max(4u, (unsigned)std::strtoul(s, nullptr, 10));
    std::cout << "[SHG] Graph M: " << shg_m << (shg_m != m ? " (GTI_SHG_M)" : "") << std::endl;
    index_heds = new hnswlib::HEDS<float>(heds_space, data->dim, max_el, shg_m, ef_build, 100, true, use_full_dim_level_skip);
    for (unsigned idx = 0; idx < entries_sec.size(); idx++)
    {
        unsigned oid = entries_sec[idx]->oid;
        index_heds->addDataPoint(data->vecs[oid].data(), (hnswlib::labeltype)idx, 1, heds_per);
    }
    int num_base = (int)entries_sec.size();
    float sample_ratio = 1.0f;
    if (const char *sr = std::getenv("GTI_SHG_SHORTCUT_SAMPLE_RATIO"))
        sample_ratio = (float)std::atof(sr);
    index_heds->buildShortcuts(num_base, sample_ratio);
    // 预留查询槽：使用不冲突的 label（插入时数据会用 0..entries_sec.size()-1，需避开）
    heds_query_slot_label = (hnswlib::labeltype)0x7FFFFFFF;
    index_heds->addDataPoint(data->vecs[entries_sec[0]->oid].data(), heds_query_slot_label, -1, heds_per);
    index_heds->markDelete(heds_query_slot_label);
    heds_query_internal_id = 0;  // S2: reset on (re)build for lightweight query reuse
    // S1: resize resultsProcessing / resultsProcessing_epoch_ for search (避免 search 时越界)
    size_t rp_size = index_heds->max_elements_ * (index_heds->maxlevel_ + 1);
    index_heds->resultsProcessing.resize(rp_size, -1.0f);
    index_heds->resultsProcessing_epoch_.resize(rp_size, 0);
#else
    index_hnsw = new n2::Hnsw(data->dim, "L2");
    for (unsigned i = 0; i < entries_sec.size(); i++)
    {
        unsigned oid = entries_sec[i]->oid;
        index_hnsw->AddData(data->vecs[oid]); // Add data
    }
    index_hnsw->Build(m, max_m0, ef_construction, n_threads); // Build graph
#endif
}

// Insert data into GTI
void GTI::insertGTI(Objects *insert_data)
{
    unsigned old_data_size = data->num;                        // Old data size
    unsigned new_data_size = old_data_size + insert_data->num; // New data size
    data->vecs.insert(data->vecs.end(), insert_data->vecs.begin(), insert_data->vecs.end());
    data->num = new_data_size;

    insertTree(old_data_size);  // Insert data into tree
    insertGraph(old_data_size); // Insert data into graph
}

// Insert data into tree
void GTI::insertTree(unsigned old_data_size)
{
    std::vector<float> dists;         // Distances to routing objects
    std::vector<unsigned> entries_in; // 0, distance calculated and pruned; 1, distance calculated and not pruned (entries without radius enlargement); 2, parent pruning
    for (unsigned i = old_data_size; i < data->num; i++)
    {
        // Create leaf entry
        GTI_Entry *entry = new GTI_Entry();
        entry->oid = (int)i;
        entry->dis_p = INF_DIS;
        entry->radius = INF_DIS;
        entry->child = NULL;

        insert(root, entry, entries_in, dists, INF_DIS); // Insert objects
    }
    std::vector<unsigned>().swap(entries_in);
    std::vector<float>().swap(dists);
}

// Insert data into graph
void GTI::insertGraph(unsigned old_data_size)
{
#ifdef GTI_USE_WOLVERINE
    std::vector<GTI_Node *> nodes;
    nodes.push_back(root);
    map.resize(data->num);
    std::fill(map.begin() + old_data_size, map.end(), -1);

    const unsigned ig_stop = (height > graph_level_offset) ? (height - graph_level_offset) : 1u;
    for (unsigned i = 0; i < ig_stop; i++)
    {
        unsigned size = nodes.size();
        for (unsigned j = 0; j < size; ++j)
        {
            if (i < ig_stop - 1)
            {
                for (unsigned k = 0; k < nodes[j]->entries.size(); k++)
                    nodes.push_back(nodes[j]->entries[k]->child);
            }
            else
            {
                for (unsigned k = 0; k < nodes[j]->entries.size(); k++)
                {
                    unsigned oid = nodes[j]->entries[k]->oid;
                    if (map[oid] == -1)
                    {
                        map[oid] = entries_sec.size();
                        entries_sec.push_back(nodes[j]->entries[k]);
                        index_wolverine->addPoint(data->vecs[oid].data(), (hnswlib::labeltype)(entries_sec.size() - 1));
                    }
                    else
                    {
                        int eid = map[oid];
                        entries_sec[eid] = nodes[j]->entries[k];
                    }
                }
            }
        }
        nodes.erase(nodes.begin(), nodes.begin() + size);
    }
#elif defined(GTI_USE_SHG)
    std::vector<GTI_Node *> nodes;
    nodes.push_back(root);
    map.resize(data->num);
    std::fill(map.begin() + old_data_size, map.end(), -1);

    const unsigned ig_stop_shg = (height > graph_level_offset) ? (height - graph_level_offset) : 1u;
    for (unsigned i = 0; i < ig_stop_shg; i++)
    {
        unsigned size = nodes.size();
        for (unsigned j = 0; j < size; ++j)
        {
            if (i < ig_stop_shg - 1)
            {
                for (unsigned k = 0; k < nodes[j]->entries.size(); k++)
                    nodes.push_back(nodes[j]->entries[k]->child);
            }
            else
            {
                for (unsigned k = 0; k < nodes[j]->entries.size(); k++)
                {
                    unsigned oid = nodes[j]->entries[k]->oid;
                    if (map[oid] == -1)
                    {
                        map[oid] = entries_sec.size();
                        entries_sec.push_back(nodes[j]->entries[k]);
                        index_heds->addDataPoint(data->vecs[oid].data(), (hnswlib::labeltype)(entries_sec.size() - 1), 1, heds_per);
                    }
                    else
                    {
                        int eid = map[oid];
                        entries_sec[eid] = nodes[j]->entries[k];
                    }
                }
            }
        }
        nodes.erase(nodes.begin(), nodes.begin() + size);
    }
#else
    index_hnsw->UnloadModel();
    std::vector<GTI_Node *> nodes;
    nodes.push_back(root);
    map.resize(data->num);
    std::fill(map.begin() + old_data_size, map.end(), -1);

    const unsigned ig_stop_n2 = (height > graph_level_offset) ? (height - graph_level_offset) : 1u;
    unsigned size = nodes.size();
    for (unsigned i = 0; i < ig_stop_n2; i++)
    {
        for (unsigned j = 0; j < size; ++j)
        {
            if (i < ig_stop_n2 - 1)
            {
                for (unsigned k = 0; k < nodes[j]->entries.size(); k++)
                {
                    nodes.push_back(nodes[j]->entries[k]->child);
                }
            }
            else
            {
                // Update entries of second level
                for (unsigned k = 0; k < nodes[j]->entries.size(); k++)
                {
                    unsigned oid = nodes[j]->entries[k]->oid;
                    if (map[oid] == -1) // Insert data into graph
                    {
                        map[oid] = entries_sec.size();
                        entries_sec.push_back(nodes[j]->entries[k]);
                        index_hnsw->AddDataM(data->vecs[oid]); // Add data
                    }
                    else // Update the entry
                    {
                        int eid = map[oid];
                        entries_sec[eid] = nodes[j]->entries[k];
                    }
                }
            }
        }
        nodes.erase(nodes.begin(), nodes.begin() + size);
        size = nodes.size();
    }

    index_hnsw->buildFromInsert(); // Insert data into graph
#endif
}

// Delete data from GTI
void GTI::deleteGTI(Objects *delete_data, bool do_rebuild)
{
    std::vector<unsigned> delete_oids;     // Ids of data needed to be deleted
    deleteTree(delete_data, delete_oids);   // Delete data from tree
    if (do_rebuild)
        deleteGraph(delete_data, delete_oids); // Delete data from graph
}

// Lazy delete: only mark oids as deleted (no tree/graph change). Search filters them via lazy_deleted_oids.
void GTI::deleteGTI_lazyOids(const std::vector<unsigned> &oids)
{
    for (unsigned oid : oids)
        lazy_deleted_oids.insert(oid);
}

// Delete data from tree
void GTI::deleteTree(Objects *delete_data, std::vector<unsigned> &delete_oids)
{
    std::vector<GTI_Node *> delete_nodes; // Nodes to delete
    std::vector<unsigned> delete_eids;    // Ids of leaf entries to delete

// Find delete data
#ifdef GTI_USE_SHG
    // SHG 查询槽复用非线程安全，串行执行 search
    for (unsigned i = 0; i < delete_data->num; i++)
#else
#pragma omp parallel for
    for (unsigned i = 0; i < delete_data->num; i++)
#endif
    {
        GTI_Node *leaf_node; // Leaf node
        unsigned leaf_eid;   // Id of leaf entry
        std::vector<Neighbor> result;
        search(delete_data->vecs[i].data(), 51, 1, result); // 1-NN search using graph

        bool is_same = true;
        if (result.empty())
        {
            is_same = false;
        }
        else
        {
            unsigned cand_oid = (unsigned)result[0].id;
            if (cand_oid >= data->vecs.size() || data->vecs[cand_oid].empty())
                is_same = false;
            else
            {
                for (unsigned j = 0; j < data->dim; j++)
                {
                    if (delete_data->vecs[i][j] != data->vecs[cand_oid][j])
                    {
                        is_same = false;
                        break;
                    }
                }
            }
        }

        if (is_same && !result.empty())
        {
            unsigned nid = result[0].nid;
            if (nid < entries_sec.size() && entries_sec[nid] != nullptr)
            {
                GTI_Node *ch = entries_sec[nid]->child;
                // 仅在「图建在叶父层」时 child 为叶子；更浅建图时 child 为内部结点，必须走 findLeaf
                if (ch != nullptr && ch->type == 1)
                {
                    leaf_node = ch;
                    leaf_eid = result[0].oid;
                }
                else
                    findLeaf(delete_data->vecs[i].data(), leaf_node, leaf_eid);
            }
            else
                is_same = false;
        }
        if (!is_same)
            findLeaf(delete_data->vecs[i].data(), leaf_node, leaf_eid); // Find the leaf of the data
        unsigned temp_oid = leaf_node->entries[leaf_eid]->oid;
        GTI_Node *temp_node = leaf_node;
        unsigned temp_eid = leaf_eid;

#pragma omp critical
        {
            delete_oids.push_back(temp_oid);
            delete_nodes.push_back(temp_node);
            delete_eids.push_back(temp_eid);
        }
    }

    // Handle underflow
    for (unsigned i = 0; i < delete_oids.size(); i++)
    {
        if (delete_nodes[i] == nullptr)
            continue;  // node was already deleted (underflow from earlier entry)
        int eid = findEntry(delete_nodes[i], delete_oids[i]);
        if (eid != -1)
        {
            GTI_Node *node_to_del = delete_nodes[i];
            deleteEntry(delete_nodes[i], eid);
            // deleteEntry may free the node on underflow; null out other refs to avoid use-after-free
            for (unsigned j = i + 1; j < delete_oids.size(); j++)
                if (delete_nodes[j] == node_to_del)
                    delete_nodes[j] = nullptr;
        }
    }
}

// Delete data from graph
void GTI::deleteGraph(Objects *delete_data, std::vector<unsigned> &delete_oids)
{
#ifdef GTI_USE_WOLVERINE
    // Direction 2 (same-leaf): maps graph label -> tree node at graph build layer (Wolverine only)
    std::unordered_map<hnswlib::labeltype, GTI_Node *> label_to_leaf_node;
    std::map<GTI_Node *, std::vector<hnswlib::labeltype>> leaf_to_labels;
    bool use_same_leaf = (std::getenv("GTI_TREE_PRIORITY_SAME_LEAF") != nullptr &&
                         std::strcmp(std::getenv("GTI_TREE_PRIORITY_SAME_LEAF"), "1") == 0);
#endif

    // Refresh entries_sec pointers from current tree (all backends)
    std::vector<GTI_Node *> nodes;
    nodes.push_back(root);
    unsigned size = nodes.size();
    const unsigned dg_stop = (height > graph_level_offset) ? (height - graph_level_offset) : 1u;
    for (unsigned i = 0; i < dg_stop; i++)
    {
        for (unsigned j = 0; j < size; ++j)
        {
            if (i < dg_stop - 1) // Upper level
                for (unsigned k = 0; k < nodes[j]->entries.size(); k++)
                    nodes.push_back(nodes[j]->entries[k]->child);
            else // Graph build level
            {
                for (unsigned k = 0; k < nodes[j]->entries.size(); k++)
                {
                    unsigned oid = nodes[j]->entries[k]->oid;
                    if (map[oid] != -1)
                    {
                        unsigned lbl = (unsigned)map[oid];
                        entries_sec[lbl] = nodes[j]->entries[k];
#ifdef GTI_USE_WOLVERINE
                        if (use_same_leaf)
                        {
                            hnswlib::labeltype gl = (hnswlib::labeltype)lbl;
                            label_to_leaf_node[gl] = nodes[j];
                            leaf_to_labels[nodes[j]].push_back(gl);
                        }
#endif
                    }
                }
            }
        }
        nodes.erase(nodes.begin(), nodes.begin() + size);
        size = nodes.size();
    }

#ifdef GTI_USE_WOLVERINE
    // Wolverine: use patchDelete (mode 4 = APPROXIMATE_TWOHOP_DELETE)
    std::vector<hnswlib::labeltype> delete_labels;
    for (unsigned oid : delete_oids)
    {
        if (map[oid] != -1)
            delete_labels.push_back((hnswlib::labeltype)map[oid]);
    }
    if (!delete_labels.empty())
    {
        // GTI_TREE_AUGMENTED_PATCH=1: use tree searchTreeRange as extra candidates (Direction 1)
        std::unordered_map<hnswlib::labeltype, std::vector<std::pair<float, hnswlib::labeltype>>> tree_candidates_per_label;
        bool use_tree_augmented = (std::getenv("GTI_TREE_AUGMENTED_PATCH") != nullptr &&
                                   std::strcmp(std::getenv("GTI_TREE_AUGMENTED_PATCH"), "1") == 0);
        if (use_tree_augmented)
        {
            float tree_radius = 5.0f;
            if (const char *s = std::getenv("GTI_TREE_PATCH_RADIUS"))
                tree_radius = (float)std::strtod(s, nullptr);
            std::unordered_set<hnswlib::labeltype> affected_labels;
            for (hnswlib::labeltype dl : delete_labels)
            {
                auto neighbors = index_wolverine->getNeighborsForLabel(dl, 0);
                for (hnswlib::labeltype nl : neighbors)
                    affected_labels.insert(nl);
            }
            std::unordered_set<unsigned> delete_oid_set(delete_oids.begin(), delete_oids.end());
            unsigned max_affected = 500; // cap to avoid huge tree search cost per batch; 0 = no limit
            if (const char *s = std::getenv("GTI_TREE_PATCH_MAX_AFFECTED"))
                max_affected = (unsigned)std::strtoul(s, nullptr, 10);
            unsigned max_cands_per_label = 256; // cap per-label candidates to avoid OOM when max_affected is large
            if (const char *s = std::getenv("GTI_TREE_PATCH_MAX_CANDS_PER_LABEL"))
                max_cands_per_label = std::max(1u, (unsigned)std::strtoul(s, nullptr, 10));
            std::vector<hnswlib::labeltype> work_list;
            for (hnswlib::labeltype afl : affected_labels)
            {
                if (max_affected > 0 && work_list.size() >= max_affected)
                    break;
                if (afl >= entries_sec.size() || entries_sec[afl] == nullptr)
                    continue;
                unsigned oid = entries_sec[afl]->oid;
                if (oid >= data->vecs.size() || data->vecs[oid].empty())
                    continue;
                work_list.push_back(afl);
            }
#pragma omp parallel for schedule(dynamic)
            for (size_t wi = 0; wi < work_list.size(); wi++)
            {
                hnswlib::labeltype afl = work_list[wi];
                unsigned oid = entries_sec[afl]->oid;
                std::vector<Neighbor> tree_result;
                searchTreeRange(data->vecs[oid].data(), tree_radius, tree_result);
                std::vector<std::pair<float, hnswlib::labeltype>> local_cands;
                for (const Neighbor &nb : tree_result)
                {
                    unsigned cand_oid = (unsigned)nb.id;
                    if (delete_oid_set.count(cand_oid) || map[cand_oid] == -1)
                        continue;
                    hnswlib::labeltype cand_label = (hnswlib::labeltype)map[cand_oid];
                    float dis_sq = nb.dis * nb.dis;
                    local_cands.push_back({dis_sq, cand_label});
                }
                // Sort by distance and keep only top max_cands_per_label to avoid OOM
                if (local_cands.size() > max_cands_per_label)
                {
                    std::partial_sort(local_cands.begin(), local_cands.begin() + max_cands_per_label,
                                      local_cands.end(),
                                      [](const std::pair<float, hnswlib::labeltype> &a,
                                         const std::pair<float, hnswlib::labeltype> &b) {
                                          return a.first < b.first;
                                      });
                    local_cands.resize(max_cands_per_label);
                }
#pragma omp critical
                {
                    if (!local_cands.empty())
                        tree_candidates_per_label[afl] = std::move(local_cands);
                }
            }
            if (tree_candidates_per_label.size() > 0)
                std::cout << "[GTI_TREE_AUGMENTED_PATCH] affected=" << affected_labels.size()
                          << " with_tree_cands=" << tree_candidates_per_label.size() << std::endl;
        }
        // GTI_TREE_PRIORITY_SAME_LEAF=1: build same_leaf_per_label for Direction 2 (same-leaf priority)
        std::unordered_map<hnswlib::labeltype, std::unordered_set<hnswlib::labeltype>> same_leaf_per_label;
        if (use_same_leaf && !leaf_to_labels.empty())
        {
            std::unordered_set<hnswlib::labeltype> delete_labels_set(delete_labels.begin(), delete_labels.end());
            std::unordered_set<hnswlib::labeltype> affected_labels;
            for (hnswlib::labeltype dl : delete_labels)
            {
                auto neighbors = index_wolverine->getNeighborsForLabel(dl, 0);
                for (hnswlib::labeltype nl : neighbors)
                    affected_labels.insert(nl);
            }
            for (hnswlib::labeltype afl : affected_labels)
            {
                auto it = label_to_leaf_node.find(afl);
                if (it == label_to_leaf_node.end())
                    continue;
                GTI_Node *leaf = it->second;
                auto jt = leaf_to_labels.find(leaf);
                if (jt == leaf_to_labels.end())
                    continue;
                for (hnswlib::labeltype lbl : jt->second)
                {
                    if (lbl != afl && delete_labels_set.count(lbl) == 0)
                        same_leaf_per_label[afl].insert(lbl);
                }
            }
            if (!same_leaf_per_label.empty())
                std::cout << "[GTI_TREE_PRIORITY_SAME_LEAF] affected=" << affected_labels.size()
                          << " with_same_leaf=" << same_leaf_per_label.size() << std::endl;
        }

        auto t0 = std::chrono::high_resolution_clock::now();
        int delete_model = 4; // APPROXIMATE_TWOHOP_DELETE (1=PINTOPOUT, 2=SEARCH, 3=TWOHOP, 4=APPROX_TWOHOP)
        // GTI_WOLVERINE_DELETE_MODEL: WolverineProMax(4) | WolverinePro(3) | Wolverine(2)
        if (const char *s = std::getenv("GTI_WOLVERINE_DELETE_MODEL"))
        {
            if (std::strcmp(s, "WolverineProMax") == 0)
                delete_model = 4;
            else if (std::strcmp(s, "WolverinePro") == 0)
                delete_model = 3;
            else if (std::strcmp(s, "Wolverine") == 0)
                delete_model = 2;
            else
                std::cerr << "[GTI] 未知 GTI_WOLVERINE_DELETE_MODEL='" << s << "', 使用 WolverineProMax(4)" << std::endl;
        }
        else if (const char *s = std::getenv("GTI_PATCH_DELETE_MODE"))
        {
            int v = (int)std::strtol(s, nullptr, 10);
            if (v >= 1 && v <= 4)
                delete_model = v;
        }
        // 倒数第三层及更浅建图：SEARCH(2) 在多批 patchDelete 后易触发 hnsw 堆损坏；默认改为 APPROX_TWOHOP(4)。
        if (graph_level_offset > 1 && delete_model == 2)
        {
            const char *force_search = std::getenv("GTI_SHALLOW_GRAPH_SEARCH_DELETE");
            if (force_search == nullptr || std::strcmp(force_search, "1") != 0)
            {
                std::cout << "[GTI] graph_level_offset>1: delete_model SEARCH(2) -> APPROX_TWOHOP(4) "
                             "(避免 PatchDelete 崩溃；强制 SEARCH 请设 GTI_SHALLOW_GRAPH_SEARCH_DELETE=1)" << std::endl;
                delete_model = 4;
            }
        }
        const char *dm_name = "WolverineProMax/APPROX_TWOHOP";
        if (delete_model == 2)
            dm_name = "Wolverine/SEARCH";
        else if (delete_model == 3)
            dm_name = "WolverinePro/TWOHOP";
        std::cout << "[GTI] Wolverine delete_model=" << delete_model << " (" << dm_name << ")" << std::endl;
        int patch_new_link_size = m;
        if (const char *s = std::getenv("GTI_PATCH_NEW_LINK_SIZE"))
        {
            int v = (int)std::strtol(s, nullptr, 10);
            if (v > 0)
                patch_new_link_size = v;
        }
        const std::unordered_map<hnswlib::labeltype, std::vector<std::pair<float, hnswlib::labeltype>>> *tree_ptr =
            (use_tree_augmented && !tree_candidates_per_label.empty()) ? &tree_candidates_per_label : nullptr;
        const std::unordered_map<hnswlib::labeltype, std::unordered_set<hnswlib::labeltype>> *same_leaf_ptr =
            (use_same_leaf && !same_leaf_per_label.empty()) ? &same_leaf_per_label : nullptr;
        // Coarse graph: parallel patchDelete races in hnswlib (mulLink / link list updates). Default to serial.
        int patch_delete_threads = (graph_level_offset > 1) ? 1 : n_threads;
        if (const char *s = std::getenv("GTI_PATCH_DELETE_THREADS"))
            patch_delete_threads = std::max(1, (int)std::strtol(s, nullptr, 10));
        if (patch_delete_threads == 1 && graph_level_offset > 1)
            std::cout << "[GTI] patchDelete threads=1 (safe mode for graph_level_offset>1)" << std::endl;
        index_wolverine->patchDelete(delete_labels, delete_model, patch_new_link_size, patch_delete_threads, tree_ptr, same_leaf_ptr);
        auto t1 = std::chrono::high_resolution_clock::now();
        std::chrono::duration<float> dt = t1 - t0;
        last_graph_update_s = dt.count();
        last_rebuild_s = 0; // Wolverine has no separate rebuild
    }
    for (unsigned i = 0; i < delete_oids.size(); i++)
    {
        unsigned oid = delete_oids[i];
        if (map[oid] != -1)
        {
            map[oid] = -1;
            lazy_deleted_oids.erase(oid);
        }
        if (oid < data->vecs.size())
            std::vector<float>().swap(data->vecs[oid]);
    }
    return;
#elif defined(GTI_USE_SHG)
    auto t0 = std::chrono::high_resolution_clock::now();
    for (unsigned oid : delete_oids)
    {
        if (map[oid] != -1)
        {
            hnswlib::labeltype gid = (hnswlib::labeltype)map[oid];
            index_heds->markDelete(gid);
            entries_sec[gid] = nullptr;
            map[oid] = -1;
            lazy_deleted_oids.insert(oid);
        }
        if (oid < data->vecs.size())
            std::vector<float>().swap(data->vecs[oid]);
    }
    auto t1 = std::chrono::high_resolution_clock::now();
    last_graph_update_s = std::chrono::duration<float>(t1 - t0).count();
    last_rebuild_s = 0;
    return;
#else

    // Delete in degree neighbors from graph (n2 path)
    unsigned delete_size = delete_oids.size();
    std::vector<unsigned> reinsert_gids;      // Ids of data needed to be reinserte
    std::vector<unsigned> reverse_cands_oids; // Possible reverse neighbor candidates
    unsigned reinsert_size = 0;
#pragma omp parallel for
    for (unsigned i = 0; i < delete_oids.size(); i++)
    {
        if (map[delete_oids[i]] == -1)
            continue;
        float radius = sqrt(index_hnsw->getRadius(map[delete_oids[i]])); // Get in degree radius
        std::vector<Neighbor> result;
        searchTreeRange(data->vecs[delete_oids[i]].data(), radius, result); // Range search to find possible reverse neighbors

        // Possible reverse neighbors = Range search result + Delete data
        std::vector<unsigned> reverse_cands_oids; // Possible reverse neighbor candidates
        for (unsigned j = 0; j < result.size(); j++)
            reverse_cands_oids.push_back(result[j].id);
        reverse_cands_oids.insert(reverse_cands_oids.end(), delete_oids.begin(), delete_oids.end());
        std::sort(reverse_cands_oids.begin(), reverse_cands_oids.end());
        reverse_cands_oids.erase(std::unique(reverse_cands_oids.begin(), reverse_cands_oids.end()), reverse_cands_oids.end());

        // Delete reverse neighbors
        std::vector<unsigned> local_reinsert_gids;
        for (unsigned j = 0; j < reverse_cands_oids.size(); j++)
        {
            if (map[reverse_cands_oids[j]] != -1 && entries_sec[map[reverse_cands_oids[j]]] != nullptr)
            {
                auto it = std::find(reinsert_gids.begin(), reinsert_gids.end(), map[reverse_cands_oids[j]]);
                if (it == reinsert_gids.end())
                {
// OpenMP critical section to avoid race condition on reinsert_gids
#pragma omp critical
                    {
                        index_hnsw->deleteNeighbor(map[reverse_cands_oids[j]], map[delete_oids[i]], local_reinsert_gids); // Delete reverse neighbors
                    }
                }
            }
        }

// OpenMP critical section to update reinsert_gids
#pragma omp critical
        {
            reinsert_gids.insert(reinsert_gids.end(), local_reinsert_gids.begin(), local_reinsert_gids.end());
        }

        // If nodes in graph have no neighbor at some level, delete them and add them into reinsert list
        unsigned local_reinsert_size = local_reinsert_gids.size();
#pragma omp critical
        {
            for (unsigned j = reinsert_size; j < reinsert_gids.size(); j++)
                if (entries_sec[reinsert_gids[j]] != nullptr)
                    delete_oids.push_back(entries_sec[reinsert_gids[j]]->oid);
            reinsert_size += local_reinsert_size;
        }
    }

    // Delete data
    for (unsigned i = 0; i < delete_size; i++)
    {
        if (map[delete_oids[i]] != -1)
        {
            index_hnsw->deleteData(map[delete_oids[i]]); // Delete data from graph
            map[delete_oids[i]] = -1;
        }
        std::vector<float>().swap(data->vecs[delete_oids[i]]); // Delete data from data list
    }

    index_hnsw->reinsertData(reinsert_gids); // Reinsert data into graph

    // Rebuild the graph model
    index_hnsw->UnloadModel();
    // Update enterpoint if it was deleted (avoids use-after-free in buildFromDeletion)
    // [TEST] Commented out to verify crash on deep/sift
    // for (size_t i = 0; i < entries_sec.size(); i++) {
    //     if (entries_sec[i] != nullptr) {
    //         index_hnsw->updateEnter((int)i);
    //         break;
    //     }
    // }
    index_hnsw->buildFromDeletion();
#endif
}

// Delete entry
void GTI::deleteEntry(GTI_Node *node, unsigned eid)
{
    if (node == nullptr || eid < 0 || eid >= node->entries.size())
    {
        printf("Invalid node or eid in deleteEntry\n");
        return;
    }

    // Clear entries_sec before delete to avoid dangling ptr (search may see nullptr, second batch crash)
    unsigned oid = node->entries[eid]->oid;
    if (oid < map.size())
    {
        int sec_id = map[oid];
        if (sec_id >= 0 && sec_id < (int)entries_sec.size())
            entries_sec[sec_id] = nullptr;
    }
    // Delete entry
    delete node->entries[eid];
    node->entries[eid] = nullptr;
    node->entries.erase(node->entries.begin() + eid);

    if (node->entries.size() == 0) // Current node is empty, delete the node and delete the entry upward
    {
        GTI_Node *parent_node = node->parent_node;
        int parent_eid = findParentEntry(parent_node, node);
        if (node->type == 1)
        {
            unsigned poid = (unsigned)parent_node->entries[parent_eid]->oid;
            if (poid < map.size() && map[poid] != -1 && map[poid] < (int)entries_sec.size())
                entries_sec[map[poid]] = nullptr;
        }
        delete node;
        node = nullptr;
        deleteEntry(parent_node, parent_eid);
    }
    else if (node == root && node->entries.size() == 1) // Delete diffusion to root
    {
        root = node->entries[0]->child;
        root->parent_node = nullptr;
        height--;
        delete node->entries[0];
        node->entries[0] = nullptr;
        node->entries.erase(node->entries.begin());
        delete node;
        node = nullptr;
    }
}

// Find the leaf of the data
void GTI::findLeaf(float *query, GTI_Node *&node, unsigned &eid)
{
    Distance distance; // Use stack allocation
    std::queue<ND> cands; // Candidate set
    cands.push(ND(root, INF_DIS, INF_DIS));
    float r = 0;

    while (!cands.empty())
    {
        ND nd = cands.front();
        cands.pop();

        if (nd.node->type == 0) // Internal node
        {
            for (unsigned i = 0; i < nd.node->entries.size(); i++)
            {
                unsigned oid = nd.node->entries[i]->oid;
                float dis_r;
                if (oid >= data->vecs.size() || data->vecs[oid].empty())
                    dis_r = 0;  // 已删除向量：用保守值以保持遍历路径，避免 findLeaf 无法到达叶节点
                else
                    dis_r = distance.getDisP(data->vecs[oid].data(), query, data->type, data->dim);
                if (abs(nd.dis_p_q - nd.node->entries[i]->dis_p) <= r + nd.node->entries[i]->radius) // Parent pruning
                {
                    float dis_min = std::max(dis_r - nd.node->entries[i]->radius, float(0.0));
                    if (dis_min <= r) // Rounting object pruning
                    {
                        cands.push(ND(nd.node->entries[i]->child, dis_min, dis_r));
                    }
                }
            }
        }
        else // Leaf node
        {
            for (unsigned i = 0; i < nd.node->entries.size(); i++)
            {
                unsigned oid = nd.node->entries[i]->oid;
                if (oid >= data->vecs.size() || data->vecs[oid].empty())
                    continue;  // 叶节点必须有效向量才能匹配
                if (abs(nd.dis_p_q - nd.node->entries[i]->dis_p) <= r)
                {
                    float dis = distance.getDisP(data->vecs[oid].data(), query, data->type, data->dim);
                    if (dis <= r)
                    {
                        bool is_same = true;
                        for (unsigned j = 0; j < data->dim; j++)
                        {
                            if (*(query + j) != data->vecs[oid][j])
                            {
                                is_same = false;
                                break;
                            }
                        }
                        if (is_same)
                        {
                            node = nd.node;
                            eid = i;
                        }
                    }
                }
            }
        }
    }
}

// kNN search for tree
void GTI::searchTreeKnn(float *query, unsigned k, std::priority_queue<Neighbor, std::vector<Neighbor>, std::less<Neighbor>> &res)
{
    std::priority_queue<ND, std::vector<ND>, std::greater<ND>> cands; // Candidate set; Ascending order
    Distance distance; // Use stack allocation

    // Initialization
    ND nd;
    nd.node = root;
    nd.dis = 0;
    cands.push(nd);
    for (unsigned i = 0; i < k; i++)
    {
        Neighbor nn;
        nn.dis = INF_DIS;
        res.push(nn);
    }

    // Search tree
    while (!cands.empty())
    {
        ND nd = cands.top();
        cands.pop();
        if (nd.dis > res.top().dis)
            break;

        for (unsigned i = 0; i < nd.node->entries.size(); i++)
        {
            bool parent_flag = true;
            if (nd.node != root)
            {
                if (abs(nd.dis_p_q - nd.node->entries[i]->dis_p) > res.top().dis + nd.node->entries[i]->radius) // Parent pruning
                    parent_flag = false;
            }
            if (parent_flag)
            {
                unsigned oid = nd.node->entries[i]->oid;
                if (oid >= data->vecs.size() || data->vecs[oid].empty())
                    continue;
                if (nd.node->type == 0) // Internal node
                {
                    float dis_r = distance.getDisP(data->vecs[oid].data(), query, data->type, data->dim);
                    float dis_min = std::max(dis_r - nd.node->entries[i]->radius, float(0.0));
                    if (dis_min <= res.top().dis) // Rounting object pruning
                    {
                        ND cand;
                        cand.node = nd.node->entries[i]->child;
                        cand.dis = dis_min;
                        cand.dis_p_q = dis_r;
                        cands.push(cand);
                        // float dis_max = dis_r + nd.node->entries[i]->radius;
                        // if (dis_max < res.top().dis) // Update top k results
                        // {
                        //     Neighbor nn;
                        //     nn.dis = dis_max;
                        //     res.push(nn);
                        //     if (res.size() > k)
                        //         res.pop();
                        // }
                    }
                }
                else // Leaf node
                {
                    float dis = distance.getDisP(data->vecs[oid].data(), query, data->type, data->dim);
                    if (dis <= res.top().dis) // Update top k results
                    {
                        Neighbor nn;
                        nn.dis = dis;
                        nn.id = oid;
                        res.push(nn);
                        if (res.size() > k)
                            res.pop();
                    }
                }
            }
        }
    }
}

// Range search for tree
void GTI::searchTreeRange(float *query, float r, std::vector<Neighbor> &results)
{
    Distance distance; // Use stack allocation
    std::queue<ND> cands; // Candidate set
    cands.push(ND(root, INF_DIS, INF_DIS));

    while (!cands.empty())
    {
        ND nd = cands.front();
        cands.pop();

        if (nd.node->type == 0) // Internal node
        {
            for (unsigned i = 0; i < nd.node->entries.size(); i++)
            {
                unsigned oid = nd.node->entries[i]->oid;
                if (oid >= data->vecs.size() || data->vecs[oid].empty())
                    continue;
                if (abs(nd.dis_p_q - nd.node->entries[i]->dis_p) <= r + nd.node->entries[i]->radius) // Parent pruning
                {
                    float dis_r = distance.getDisP(data->vecs[oid].data(), query, data->type, data->dim);
                    float dis_min = std::max(dis_r - nd.node->entries[i]->radius, float(0.0));
                    if (dis_min <= r) // Rounting object pruning
                    {
                        cands.push(ND(nd.node->entries[i]->child, dis_min, dis_r));
                    }
                }
            }
        }
        else // Leaf node
        {
            for (unsigned i = 0; i < nd.node->entries.size(); i++)
            {
                unsigned oid = nd.node->entries[i]->oid;
                if (oid >= data->vecs.size() || data->vecs[oid].empty())
                    continue;
                if (abs(nd.dis_p_q - nd.node->entries[i]->dis_p) <= r)
                {
                    float dis = distance.getDisP(data->vecs[oid].data(), query, data->type, data->dim);
                    if (dis <= r)
                        results.push_back(Neighbor(oid, dis, true));
                }
            }
        }
    }
}

// Search
void GTI::search(float *query, unsigned L, unsigned K, std::vector<Neighbor> &results)
{
#ifdef GTI_USE_WOLVERINE
    unsigned base_ef = std::max(50u, 5u * L);
    unsigned graph_k = L;
    unsigned ef = base_ef;
    if (graph_level_offset > 1)
    {
        graph_k = shallowGraphSearchK(L, entries_sec.size());
        ef = shallowGraphSearchEf(graph_k, base_ef);
    }
    index_wolverine->setEf(ef);
    auto pq = index_wolverine->searchKnn(query, graph_k);
    results.clear();
    if (graph_level_offset <= 1)
    {
        while (!pq.empty())
        {
            float d = pq.top().first;
            hnswlib::labeltype eid = pq.top().second;
            pq.pop();
            if (eid < entries_sec.size() && entries_sec[eid] != nullptr)
            {
                unsigned oid = entries_sec[eid]->oid;
                if (lazy_deleted_oids.find(oid) == lazy_deleted_oids.end())
                {
                    float dis = (float)std::sqrt(std::max(0.0, (double)d));
                    results.push_back(Neighbor((int)oid, dis, (unsigned)eid, true, 0));  // oid=0: routing obj at leaf entry 0
                }
            }
        }
        std::reverse(results.begin(), results.end());  // pq gives furthest-first, need nearest-first for recall
    }
    else
    {
        // Shallow graph: each graph vertex covers a subtree; expand to all leaf oids and re-rank by true distance.
        Distance distance;
        std::unordered_map<unsigned, std::pair<float, unsigned>> best; // oid -> (true dis, graph label eid)
        while (!pq.empty())
        {
            hnswlib::labeltype eid = pq.top().second;
            pq.pop();
            if (eid >= entries_sec.size() || entries_sec[eid] == nullptr)
                continue;
            GTI_Entry *ent = entries_sec[eid];
            std::vector<unsigned> oids;
            oids.reserve(512);
            if (ent->child == nullptr)
                oids.push_back(ent->oid);
            else
                collectLeafOidsUnderNode(ent->child, oids);
            for (unsigned oid : oids)
            {
                if (lazy_deleted_oids.find(oid) != lazy_deleted_oids.end())
                    continue;
                if (oid >= data->vecs.size() || data->vecs[oid].empty())
                    continue;
                float dis = distance.getDisP(data->vecs[oid].data(), query, data->type, data->dim);
                auto it = best.find(oid);
                if (it == best.end() || dis < it->second.first)
                    best[oid] = std::make_pair(dis, (unsigned)eid);
            }
        }
        std::vector<Neighbor> expanded;
        expanded.reserve(best.size());
        for (const auto &kv : best)
            expanded.push_back(Neighbor((int)kv.first, kv.second.first, kv.second.second, true, 0));
        std::sort(expanded.begin(), expanded.end(), [](const Neighbor &a, const Neighbor &b) {
            return a.dis < b.dis;
        });
        unsigned out_n = std::min(L, (unsigned)expanded.size());
        results.assign(expanded.begin(), expanded.begin() + out_n);
    }
#elif defined(GTI_USE_SHG)
    bool use_lightweight = (std::getenv("GTI_SHG_LIGHTWEIGHT_QUERY") != nullptr);
    hnswlib::tableint qid = 0;
    if (use_lightweight && heds_query_internal_id != 0) {
        index_heds->overwriteQuerySlotData(query, heds_query_internal_id);
        qid = heds_query_internal_id;
    } else {
        index_heds->addDataPoint(query, heds_query_slot_label, -1, heds_per, true);
        auto lit = index_heds->label_lookup_.find(heds_query_slot_label);
        if (lit == index_heds->label_lookup_.end())
        {
            index_heds->markDelete(heds_query_slot_label);
            results.clear();
            return;
        }
        qid = lit->second;
        if (use_lightweight) heds_query_internal_id = qid;
    }
    unsigned graph_k_shg = L;
    if (graph_level_offset > 1)
        graph_k_shg = shallowGraphSearchK(L, entries_sec.size());
    Query q((int)qid, (int)graph_k_shg);
    {
        unsigned ef = 10;
        if (const char *s = std::getenv("GTI_SHG_EF_SEARCH"))
            ef = (unsigned)std::strtoul(s, nullptr, 10);
        if (ef == 0)
            ef = std::max(10u, 5u * L);
        if (graph_level_offset > 1)
            ef = shallowGraphSearchEf(graph_k_shg, std::max(ef, std::max(10u, 5u * L)));
        index_heds->setEf(ef);
    }
    auto pq = index_heds->searchKnnShortcuts(q);
    results.clear();
    std::vector<Neighbor> tmp;
    while (!pq.empty())
    {
        auto p = pq.top();
        pq.pop();
        hnswlib::labeltype gid = p.second;
        float dist_sq = (float)p.first;
        if (gid >= entries_sec.size() || entries_sec[gid] == nullptr)
            continue;
        unsigned oid = entries_sec[gid]->oid;
        if (lazy_deleted_oids.find(oid) != lazy_deleted_oids.end())
            continue;
        GTI_Node *leaf = entries_sec[gid]->child;
        unsigned leaf_eid = 0;
        if (leaf != nullptr)
        {
            for (unsigned e = 0; e < leaf->entries.size(); e++)
            {
                if (leaf->entries[e] != nullptr && leaf->entries[e]->oid == (int)oid)
                {
                    leaf_eid = e;
                    break;
                }
            }
        }
        tmp.push_back(Neighbor((int)oid, (float)std::sqrt(std::max(0.0, (double)dist_sq)), (unsigned)gid, true, leaf_eid));
    }
    if (graph_level_offset <= 1)
    {
        results.assign(tmp.rbegin(), tmp.rend());
    }
    else
    {
        Distance distance;
        std::unordered_map<unsigned, std::pair<float, unsigned>> best; // oid -> (true dis, gid)
        for (const Neighbor &nw : tmp)
        {
            hnswlib::labeltype gid = (hnswlib::labeltype)nw.nid;
            if (gid >= entries_sec.size() || entries_sec[gid] == nullptr)
                continue;
            GTI_Entry *ent = entries_sec[gid];
            std::vector<unsigned> oids;
            oids.reserve(512);
            if (ent->child == nullptr)
                oids.push_back(ent->oid);
            else
                collectLeafOidsUnderNode(ent->child, oids);
            for (unsigned oid : oids)
            {
                if (lazy_deleted_oids.find(oid) != lazy_deleted_oids.end())
                    continue;
                if (oid >= data->vecs.size() || data->vecs[oid].empty())
                    continue;
                float dis = distance.getDisP(data->vecs[oid].data(), query, data->type, data->dim);
                auto it = best.find(oid);
                if (it == best.end() || dis < it->second.first)
                    best[oid] = std::make_pair(dis, (unsigned)gid);
            }
        }
        std::vector<Neighbor> expanded;
        expanded.reserve(best.size());
        for (const auto &kv : best)
            expanded.push_back(Neighbor((int)kv.first, kv.second.first, kv.second.second, true, 0));
        std::sort(expanded.begin(), expanded.end(), [](const Neighbor &a, const Neighbor &b) {
            return a.dis < b.dis;
        });
        unsigned out_n = std::min(L, (unsigned)expanded.size());
        results.assign(expanded.begin(), expanded.begin() + out_n);
    }
    if (!use_lightweight) index_heds->markDelete(heds_query_slot_label);
#else
    std::vector<std::pair<int, float>> results_hnsw; // Results of search HNSW

    std::vector<float> vec;
    vec.assign(query, query + data->dim);
    unsigned graph_k_n2 = L;
    int ef_search_n2 = (int)(5 * L);
    if (graph_level_offset > 1)
    {
        graph_k_n2 = shallowGraphSearchK(L, entries_sec.size());
        ef_search_n2 = (int)shallowGraphSearchEf(graph_k_n2, std::max(50u, 5u * L));
    }
    results.clear();
    index_hnsw->SearchByVectorM(vec, graph_k_n2, ef_search_n2, results_hnsw, results, entries_sec, data->vecs);
    if (graph_level_offset > 1)
    {
        std::vector<Neighbor> expanded_n2;
        expandShallowGraphFromN2ResultPool(query, L, data, entries_sec, lazy_deleted_oids, results, expanded_n2);
        results.swap(expanded_n2);
    }
#endif
}

// Exact k-NN search
void GTI::searchExactKnn(float *query, unsigned L, unsigned K, std::vector<Neighbor> &results,
                         std::priority_queue<Neighbor, std::vector<Neighbor>, std::less<Neighbor>> &res)
{
#ifdef GTI_USE_WOLVERINE
    unsigned base_ef_ex = std::max(50u, 5u * L);
    unsigned graph_k_ex = L;
    unsigned ef_ex = base_ef_ex;
    if (graph_level_offset > 1)
    {
        graph_k_ex = shallowGraphSearchK(L, entries_sec.size());
        ef_ex = shallowGraphSearchEf(graph_k_ex, base_ef_ex);
    }
    index_wolverine->setEf(ef_ex);
    auto pq = index_wolverine->searchKnn(query, graph_k_ex);
    results.clear();
    if (graph_level_offset <= 1)
    {
        while (!pq.empty())
        {
            float d = pq.top().first;
            hnswlib::labeltype eid = pq.top().second;
            pq.pop();
            if (eid < entries_sec.size() && entries_sec[eid] != nullptr)
            {
                unsigned oid = entries_sec[eid]->oid;
                if (lazy_deleted_oids.find(oid) == lazy_deleted_oids.end())
                {
                    float dis = (float)std::sqrt(std::max(0.0, (double)d));
                    results.push_back(Neighbor((int)oid, dis, (unsigned)eid, true, 0));
                }
            }
        }
        std::reverse(results.begin(), results.end());
    }
    else
    {
        Distance distance;
        std::unordered_map<unsigned, std::pair<float, unsigned>> best;
        while (!pq.empty())
        {
            hnswlib::labeltype eid = pq.top().second;
            pq.pop();
            if (eid >= entries_sec.size() || entries_sec[eid] == nullptr)
                continue;
            GTI_Entry *ent = entries_sec[eid];
            std::vector<unsigned> oids;
            oids.reserve(512);
            if (ent->child == nullptr)
                oids.push_back(ent->oid);
            else
                collectLeafOidsUnderNode(ent->child, oids);
            for (unsigned oid : oids)
            {
                if (lazy_deleted_oids.find(oid) != lazy_deleted_oids.end())
                    continue;
                if (oid >= data->vecs.size() || data->vecs[oid].empty())
                    continue;
                float dis = distance.getDisP(data->vecs[oid].data(), query, data->type, data->dim);
                auto it = best.find(oid);
                if (it == best.end() || dis < it->second.first)
                    best[oid] = std::make_pair(dis, (unsigned)eid);
            }
        }
        std::vector<Neighbor> expanded;
        expanded.reserve(best.size());
        for (const auto &kv : best)
            expanded.push_back(Neighbor((int)kv.first, kv.second.first, kv.second.second, true, 0));
        std::sort(expanded.begin(), expanded.end(), [](const Neighbor &a, const Neighbor &b) {
            return a.dis < b.dis;
        });
        unsigned out_n = std::min(L, (unsigned)expanded.size());
        results.assign(expanded.begin(), expanded.begin() + out_n);
    }
    // Fill res with top K for tree refinement (pad with INF_DIS if fewer than K)
    for (unsigned i = 0; i < K; i++)
    {
        if (i < results.size())
            res.push(results[i]);
        else
            res.push(Neighbor(-1, INF_DIS, 0, true, 0));
    }
    searchTree(query, K, res);
    results.resize(K);
    unsigned i = 0;
    while (!res.empty())
    {
        results[K - 1 - i] = res.top();
        res.pop();
        i++;
    }
#elif defined(GTI_USE_SHG)
    bool use_lightweight = (std::getenv("GTI_SHG_LIGHTWEIGHT_QUERY") != nullptr);
    hnswlib::tableint qid = 0;
    if (use_lightweight && heds_query_internal_id != 0) {
        index_heds->overwriteQuerySlotData(query, heds_query_internal_id);
        qid = heds_query_internal_id;
    } else {
        index_heds->addDataPoint(query, heds_query_slot_label, -1, heds_per, true);
        auto lit = index_heds->label_lookup_.find(heds_query_slot_label);
        if (lit == index_heds->label_lookup_.end())
        {
            index_heds->markDelete(heds_query_slot_label);
            results.clear();
            for (unsigned i = 0; i < K; i++)
                res.push(Neighbor(-1, INF_DIS, 0, true, 0));
            searchTree(query, K, res);
            results.resize(K);
            unsigned j = 0;
            while (!res.empty())
            {
                results[K - 1 - j] = res.top();
                res.pop();
                j++;
            }
            return;
        }
        qid = lit->second;
        if (use_lightweight) heds_query_internal_id = qid;
    }
    unsigned graph_k_shg_ex = L;
    if (graph_level_offset > 1)
        graph_k_shg_ex = shallowGraphSearchK(L, entries_sec.size());
    Query q((int)qid, (int)graph_k_shg_ex);
    unsigned ef_exact = 10;
    if (const char *s = std::getenv("GTI_SHG_EF_SEARCH"))
        ef_exact = (unsigned)std::strtoul(s, nullptr, 10);
    if (ef_exact == 0)
        ef_exact = std::max(10u, 5u * L);
    if (graph_level_offset > 1)
        ef_exact = shallowGraphSearchEf(graph_k_shg_ex, std::max(ef_exact, std::max(10u, 5u * L)));
    index_heds->setEf(ef_exact);
    auto pq = index_heds->searchKnnShortcuts(q);
    results.clear();
    std::vector<Neighbor> tmp;
    while (!pq.empty())
    {
        auto p = pq.top();
        pq.pop();
        hnswlib::labeltype gid = p.second;
        float dist_sq = (float)p.first;
        if (gid >= entries_sec.size() || entries_sec[gid] == nullptr)
            continue;
        unsigned oid = entries_sec[gid]->oid;
        if (lazy_deleted_oids.find(oid) != lazy_deleted_oids.end())
            continue;
        GTI_Node *leaf = entries_sec[gid]->child;
        unsigned leaf_eid = 0;
        if (leaf != nullptr)
        {
            for (unsigned e = 0; e < leaf->entries.size(); e++)
            {
                if (leaf->entries[e] != nullptr && leaf->entries[e]->oid == (int)oid)
                {
                    leaf_eid = e;
                    break;
                }
            }
        }
        tmp.push_back(Neighbor((int)oid, (float)std::sqrt(std::max(0.0, (double)dist_sq)), (unsigned)gid, true, leaf_eid));
    }
    if (graph_level_offset <= 1)
    {
        std::reverse(tmp.begin(), tmp.end());
        results.assign(tmp.begin(), tmp.end());
    }
    else
    {
        Distance distance;
        std::unordered_map<unsigned, std::pair<float, unsigned>> best;
        for (const Neighbor &nw : tmp)
        {
            hnswlib::labeltype gid = (hnswlib::labeltype)nw.nid;
            if (gid >= entries_sec.size() || entries_sec[gid] == nullptr)
                continue;
            GTI_Entry *ent = entries_sec[gid];
            std::vector<unsigned> oids;
            oids.reserve(512);
            if (ent->child == nullptr)
                oids.push_back(ent->oid);
            else
                collectLeafOidsUnderNode(ent->child, oids);
            for (unsigned oid : oids)
            {
                if (lazy_deleted_oids.find(oid) != lazy_deleted_oids.end())
                    continue;
                if (oid >= data->vecs.size() || data->vecs[oid].empty())
                    continue;
                float dis = distance.getDisP(data->vecs[oid].data(), query, data->type, data->dim);
                auto it = best.find(oid);
                if (it == best.end() || dis < it->second.first)
                    best[oid] = std::make_pair(dis, (unsigned)gid);
            }
        }
        std::vector<Neighbor> expanded;
        expanded.reserve(best.size());
        for (const auto &kv : best)
            expanded.push_back(Neighbor((int)kv.first, kv.second.first, kv.second.second, true, 0));
        std::sort(expanded.begin(), expanded.end(), [](const Neighbor &a, const Neighbor &b) {
            return a.dis < b.dis;
        });
        unsigned out_n = std::min(L, (unsigned)expanded.size());
        results.assign(expanded.begin(), expanded.begin() + out_n);
    }
    if (!use_lightweight) index_heds->markDelete(heds_query_slot_label);
    for (unsigned i = 0; i < K; i++)
    {
        if (i < results.size())
            res.push(results[i]);
        else
            res.push(Neighbor(-1, INF_DIS, 0, true, 0));
    }
    searchTree(query, K, res);
    results.resize(K);
    unsigned j = 0;
    while (!res.empty())
    {
        results[K - 1 - j] = res.top();
        res.pop();
        j++;
    }
#else
    // Search graph to get initial results
    std::vector<std::pair<int, float>> results_hnsw; // Results of search HNSW
    std::vector<float> vec;
    vec.assign(query, query + data->dim);
    unsigned graph_k_n2ex = L;
    int ef_search_n2ex = (int)(5 * L);
    if (graph_level_offset > 1)
    {
        graph_k_n2ex = shallowGraphSearchK(L, entries_sec.size());
        ef_search_n2ex = (int)shallowGraphSearchEf(graph_k_n2ex, std::max(50u, 5u * L));
    }
    results.clear();
    index_hnsw->SearchByVectorM(vec, graph_k_n2ex, ef_search_n2ex, results_hnsw, results, entries_sec, data->vecs);
    if (graph_level_offset > 1)
    {
        std::vector<Neighbor> expanded_n2ex;
        expandShallowGraphFromN2ResultPool(query, L, data, entries_sec, lazy_deleted_oids, results, expanded_n2ex);
        results.swap(expanded_n2ex);
    }

    // Search tree using graph results to get final k-NNs
    for (unsigned i = 0; i < K; i++)
    {
        Neighbor nn;
        nn.dis = sqrt(results[i].dis);
        nn.id = results[i].id;
        res.push(nn);
    }
    searchTree(query, K, res);
    unsigned i = 0;
    while (!res.empty())
    {
        results[K - 1 - i] = res.top();
        res.pop();
        i++;
    }
#endif
}

// Search tree using graph results
void GTI::searchTree(float *query, unsigned k, std::priority_queue<Neighbor, std::vector<Neighbor>, std::less<Neighbor>> &res)
{
    std::priority_queue<ND, std::vector<ND>, std::greater<ND>> cands; // Candidate set; Ascending order
    Distance distance; // Use stack allocation

    // Initialization
    ND nd;
    nd.node = root;
    nd.dis = 0;
    cands.push(nd);
    // for (unsigned i = 0; i < k; i++)
    // {
    //     Neighbor nn;
    //     nn.dis = INF_DIS;
    //     res.push(nn);
    // }

    // Search tree
    while (!cands.empty())
    {
        ND nd = cands.top();
        cands.pop();
        if (nd.dis > res.top().dis)
            break;

        for (unsigned i = 0; i < nd.node->entries.size(); i++)
        {
            bool parent_flag = true;
            if (nd.node != root)
            {
                if (abs(nd.dis_p_q - nd.node->entries[i]->dis_p) > res.top().dis + nd.node->entries[i]->radius) // Parent pruning
                    parent_flag = false;
            }
            if (parent_flag)
            {
                unsigned oid = nd.node->entries[i]->oid;
                if (oid >= data->vecs.size() || data->vecs[oid].empty())
                    continue;
                if (nd.node->type == 0) // Internal node
                {
                    float dis_r = distance.getDisP(data->vecs[oid].data(), query, data->type, data->dim);
                    float dis_min = std::max(dis_r - nd.node->entries[i]->radius, float(0.0));
                    if (dis_min <= res.top().dis) // Rounting object pruning
                    {
                        ND cand;
                        cand.node = nd.node->entries[i]->child;
                        cand.dis = dis_min;
                        cand.dis_p_q = dis_r;
                        cands.push(cand);
                        // float dis_max = dis_r + nd.node->entries[i]->radius;
                        // if (dis_max < res.top().dis) // Update top k results
                        // {
                        //     Neighbor nn;
                        //     nn.dis = dis_max;
                        //     res.push(nn);
                        //     if (res.size() > k)
                        //         res.pop();
                        // }
                    }
                }
                else // Leaf node
                {
                    float dis = distance.getDisP(data->vecs[oid].data(), query, data->type, data->dim);
                    if (dis <= res.top().dis) // Update top k results
                    {
                        Neighbor nn;
                        nn.dis = dis;
                        nn.id = oid;
                        res.push(nn);
                        if (res.size() > k)
                            res.pop();
                    }
                }
            }
        }
    }
}

// Get the size of tree
void GTI::getTreeSize()
{
    std::vector<GTI_Node *> nodes;
    nodes.push_back(root);

    // Get the size of tree
    unsigned size = nodes.size();
    for (unsigned i = 0; i < height; i++)
    {
        for (unsigned j = 0; j < size; ++j)
        {
            for (unsigned k = 0; k < nodes[j]->entries.size(); k++)
            {
                tree_size += sizeof(unsigned) + 2 * sizeof(float) + sizeof(GTI_Node *);
                if (i < height - 1) // Upper level
                {
                    nodes.push_back(nodes[j]->entries[k]->child);
                }
            }
            // tree_size += sizeof(unsigned) + sizeof(GTI_Node *) + sizeof(GTI_Entry *) * nodes[j]->entries.size();
        }
        nodes.erase(nodes.begin(), nodes.begin() + size);
        size = nodes.size();
    }
}

#ifdef GTI_USE_SHG
void GTI::rebuildShortcuts()
{
    if (index_heds == nullptr) return;
    int num_base = (int)entries_sec.size();
    float sample_ratio = 1.0f;
    if (const char *sr = std::getenv("GTI_SHG_SHORTCUT_SAMPLE_RATIO"))
        sample_ratio = (float)std::atof(sr);
    index_heds->buildShortcuts(num_base, sample_ratio);
    if (const char *s = std::getenv("GTI_SHG_VERBOSE"); s && s[0] == '1')
        std::cout << "[D] rebuildShortcuts done, shortcutsSize=" << index_heds->shortcutsSize << std::endl;
}

int GTI::getHEDSLayerCount() const
{
    return index_heds != nullptr ? (int)index_heds->maxlevel_ : -1;
}

void GTI::printAndResetLevelsSkipStats()
{
    if (index_heds == nullptr) return;
    if (const char *s = std::getenv("GTI_SHG_VERBOSE_LEVELSKIP"); s && s[0] == '1')
    {
        long long calls = index_heds->levelsSkip_call_count.load();
        long long skipped = index_heds->levelsSkip_total_levels_skipped.load();
        std::cout << "[F] levelsSkip: calls=" << calls << " total_levels_skipped=" << skipped
                  << (calls > 0 ? " avg=" + std::to_string((double)skipped / calls) : "") << std::endl;
    }
    index_heds->levelsSkip_call_count = 0;
    index_heds->levelsSkip_total_levels_skipped = 0;
}
#endif