// GTI
// Created by Ruiyao Ma on 24-02-22

#pragma once
#include <iostream>
#include <algorithm>
#include <unistd.h>
#include <chrono>
#include <queue>
#include <stack>
#include <thread>
#include <omp.h>
#include <unordered_set>
#include "gti_entry.h"
#include "gti_node.h"
#include "objects.h"
#include "distance.h"
#include "neighbor.h"
#ifndef GTI_USE_WOLVERINE
#ifndef GTI_USE_SHG
#include "n2/hnsw.h"
#else
#include "hnswlib.h"
#endif
#else
#include "hnswlib.h"
#endif
#include "lsh_index.h"

bool compareEnDisp(GTI_Entry *e1, GTI_Entry *e2); // Comparison function for two entries

// Split strategy enum
enum class SplitStrategy {
    LB,  // Baseline/LB strategy
    MST  // MST-based split strategy
};

// MST split configuration structure
struct MSTSplitConfig {
    int full_mst_threshold = 200;      // Threshold for using full MST vs sampling
    int sample_size = 300;              // Sample size when using sampling
    float balance_min_frac = 0.1f;      // Minimum fraction for balanced split
    bool use_sampling_if_large = false; // Whether to use sampling for large sets
    unsigned seed = 42;                 // Random seed
    int cut_edge_candidates = 10;        // Number of candidate cut edges to evaluate
    int medoid_candidate_k = 64;        // Number of medoid candidates (medoid_k)
    bool use_adaptive_params = false;    // Whether to use adaptive parameters
    bool use_overlap_minimization = false; // Whether to minimize overlap
    bool use_two_stage_refine = false;   // Whether to use two-stage refinement
    int max_iterations = 5;             // Maximum iterations for medoid refinement
    bool use_smart_sampling = false;     // Whether to use smart sampling
};

class GTI
{
public:
    Objects *data; // Data

    unsigned capacity_up_l; // Upper node capacity for leaf node
    unsigned capacity_up_i; // Upper node capacity for internal node
    GTI_Node *root;         // Root node
    unsigned height;        // Tree height
    unsigned graph_level_offset = 1; // Graph build level offset from leaves (1=original leaf-parent level)
    double tree_size = 0;   // Size of the tree

    std::vector<GTI_Entry *> entries_sec; // Entries of configured graph build layer
    std::vector<int> map;                 // Map object id to entry id in graph build layer
    std::unordered_set<unsigned> lazy_deleted_oids; // Oids lazy-deleted (not yet rebuilt from graph)
    float last_graph_update_s = 0;  // Time for deleteGraph graph ops (excluding buildFromDeletion)
    float last_rebuild_s = 0;       // Time for buildFromDeletion only
#ifndef GTI_USE_WOLVERINE
#ifndef GTI_USE_SHG
    n2::Hnsw *index_hnsw = nullptr;      // HNSW Graph at second level (n2)
#else
    hnswlib::HEDS<float> *index_heds = nullptr;   // SHG/HEDS graph backend
    hnswlib::L2Space *heds_space = nullptr;       // L2 space for SHG
    Performance heds_per;                         // SHG performance (from basis.h)
    hnswlib::labeltype heds_query_slot_label = 0;  // Query slot label for reuse
    hnswlib::tableint heds_query_internal_id = 0; // Query slot internal id
#endif
#else
    hnswlib::HierarchicalNSW<float> *index_wolverine = nullptr;  // Wolverine graph backend
    hnswlib::L2Space *wolverine_space = nullptr;                // L2 space for Wolverine
#endif
    int m;
    int max_m0;
    int ef_construction;
    int n_threads; // Number of threads to build graph

    float time_split = 0;

    // LSH index for second-level entries (lightweight seed selection)
    LSHIndex *lsh_sec = nullptr;
    int lsh_tables = 4;           // Number of LSH hash tables (L)
    int lsh_k = 4;                // Number of hash functions per table (K)
    int lsh_seed_count = 4;       // Number of seeds for multi-seed init
    int lsh_dim_low = 16;         // Low dimension for LSH random projection
    int ef_seed = 32;
    int lsh_ef_multiplier = 5;    // When LSH enabled: ef = lsh_ef_multiplier * L (5=baseline)
    bool lsh_enabled = true;      // Enable/disable LSH (pluggable)

    // MST split strategy and configuration
    SplitStrategy split_strategy = SplitStrategy::LB;
    MSTSplitConfig mst_cfg;
    unsigned mst_attempts = 0;
    unsigned mst_used = 0;
    unsigned mst_fallback_count = 0;

    // Load split configuration from environment variables
    void loadSplitConfigFromEnv();

    // MST-based promotion method
    void promote_mst(const std::vector<GTI_Entry *> &entries,
                      int &p1_idx,
                      int &p2_idx,
                      MSTSplitConfig const &cfg,
                      std::vector<float> *out_dists1,
                      std::vector<float> *out_dists2);

    GTI() {};
    ~GTI() {
        // Release LSH index
        if (lsh_sec != nullptr) {
            delete lsh_sec;
            lsh_sec = nullptr;
        }

        // Release HNSW index
#ifndef GTI_USE_WOLVERINE
#ifndef GTI_USE_SHG
        if (index_hnsw != nullptr) {
            delete index_hnsw;
            index_hnsw = nullptr;
        }
#else
        if (index_heds != nullptr) {
            delete index_heds;
            index_heds = nullptr;
        }
        if (heds_space != nullptr) {
            delete heds_space;
            heds_space = nullptr;
        }
#endif
#else
        if (index_wolverine != nullptr) {
            delete index_wolverine;
            index_wolverine = nullptr;
        }
        if (wolverine_space != nullptr) {
            delete wolverine_space;
            wolverine_space = nullptr;
        }
#endif

        // Clear entries_sec before releasing tree to avoid double deletion
        entries_sec.clear();

        // Release tree structure recursively
        releaseTree(root);

        // Clear other vectors
        map.clear();
    };

    void releaseTree(GTI_Node *node) {
        if (node == nullptr) return;

        // Recursively release all child nodes
        for (auto entry : node->entries) {
            if (entry != nullptr) {
                if (entry->child != nullptr) {
                    releaseTree(entry->child);
                }
                delete entry;
                entry = nullptr;
            }
        }

        // Clear the entries vector
        node->entries.clear();

        // Delete the node itself
        delete node;
    }

    void buildGTI(unsigned capacity_up_i, unsigned capacity_up_l, int m, Objects *data);                                        // Build GTI
    void init(unsigned capacity_up_i, unsigned capacity_up_l, int m, Objects *data);                                            // Initialize GTI
    GTI_Node *findParentNode(GTI_Node *N, GTI_Node *node);                                                                      // Find parent node
    int findParentEntry(GTI_Node *parent, GTI_Node *node);                                                                      // Find parent entry
    int findEntry(GTI_Node *node, unsigned oid);                                                                                // Find entry id in the node
    void insertAll();                                                                                                           // Insert all objects to tree
    void insert(GTI_Node *node, GTI_Entry *entry, std::vector<unsigned> &entries_in, std::vector<float> &dists, float dis_p2o); // Insert objects
    void split(GTI_Node *node, GTI_Entry *entry);                                                                               // Split node
    // M_LB_DIST1 methods to choose two new routing objects
    void promoteLb(std::vector<GTI_Entry *> &entries,
                   int *min_oid,
                   GTI_Node *parent_node,
                   GTI_Node *node,
                   std::vector<float> &dists_split);
    // Divide the entries into two nodes using generalized hyperplane
    void partitionGh(std::vector<GTI_Entry *> &entries,
                     GTI_Node *node1,
                     GTI_Node *node2,
                     GTI_Entry *entry1,
                     GTI_Entry *entry2,
                     int oid1,
                     int oid2,
                     std::vector<float> dists_split);
    void buildGraphSec(); // Build graph at configured level (default: original second level)

    void insertGTI(Objects *insert_data);     // Insert data into GTI
    void insertTree(unsigned old_data_size);  // Insert data into tree
    void insertGraph(unsigned old_data_size); // Insert data into graph

    void deleteGTI(Objects *delete_data, bool do_rebuild = true);                // Delete data from GTI
    void deleteGTI_lazyOids(const std::vector<unsigned> &oids);                  // Lazy delete by oids only (no tree/graph change)
    void deleteGTI_fromOids(const std::vector<unsigned> &delete_oids);        // Full graph delete+rebuild when tree already removed (e.g. after lazy deletes)
    void deleteTree(Objects *delete_data, std::vector<unsigned> &delete_oids);  // Delete data from tree
    void deleteGraph(Objects *delete_data, std::vector<unsigned> &delete_oids); // Delete data from graph
    void deleteEntry(GTI_Node *node, unsigned eid);                             // Delete entry
    void findLeaf(float *query, GTI_Node *&node, unsigned &eid);                // Find the leaf of the data

    void searchTreeKnn(float *query,
                       unsigned k,
                       std::priority_queue<Neighbor, std::vector<Neighbor>, std::less<Neighbor>> &res); // k-NN search for tree
    void searchTreeRange(float *query, float r, std::vector<Neighbor> &results);                        // Range search for tree
    void search(float *query, unsigned L, unsigned K, std::vector<Neighbor> &results);                  // Search
    void searchExactKnn(float *query,
                        unsigned L,
                        unsigned K,
                        std::vector<Neighbor> &results,
                        std::priority_queue<Neighbor, std::vector<Neighbor>, std::less<Neighbor>> &res); // Exact k-NN search
    void searchTree(float *query,
                    unsigned k,
                    std::priority_queue<Neighbor, std::vector<Neighbor>, std::less<Neighbor>> &res); // Search tree using graph results

    void getTreeSize(); // Get the size of tree

#ifdef GTI_USE_SHG
    void rebuildShortcuts();  // D: rebuild Shortcuts after insert (GTI_SHG_REBUILD_AFTER_INSERT=1)
    int getHEDSLayerCount() const;  // return HNSW maxlevel for logging
    void printAndResetLevelsSkipStats();  // F: print levelsSkip counters when GTI_SHG_VERBOSE_LEVELSKIP=1
#endif
};