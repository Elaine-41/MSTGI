#include "lsh_index.h"
#include <cstring>
#include <cstdio>
#include <queue>
#include <unordered_set>
#include <algorithm>
#include <omp.h>

#ifdef __GNUC__
#include <cstring>
#elif defined _MSC_VER
#include <intrin.h>
#endif

LSHIndex::LSHIndex(int L_, int K_, int dim_, int dim_low_, float W_) 
    : L(L_), K(K_), dim(dim_), dim_low(dim_low_), W(W_), N(0), u(16), table_size_(0) {
    S = L * K;
    hashval = nullptr;
    hashTables = nullptr;
    rndAs = nullptr;
    rndBs = nullptr;
    projMatrix = nullptr;
    deleted_count = 0;
    
    // Initialize random projection matrix
    projMatrix = new float*[dim];
    std::mt19937 rng(42); // Fixed seed for reproducibility
    std::normal_distribution<float> nd(0.0f, 1.0f);
    for (int i = 0; i < dim; i++) {
        projMatrix[i] = new float[dim_low];
        for (int j = 0; j < dim_low; j++) {
            projMatrix[i][j] = nd(rng);
        }
    }
    
    initHash();
}

LSHIndex::~LSHIndex() {
    // Clean up hash values
    if (hashval) {
        for (int i = 0; i < N; i++) {
            delete[] hashval[i];
        }
        delete[] hashval;
    }
    
    // Clean up hash tables
    if (hashTables) {
        for (int i = 0; i < L; i++) {
            delete[] hashTables[i];
        }
        delete[] hashTables;
    }
    
    // Clean up hash parameters
    if (rndAs) {
        for (int i = 0; i < S; i++) {
            delete[] rndAs[i];
        }
        delete[] rndAs;
    }
    delete[] rndBs;
    
    // Clean up projection matrix
    if (projMatrix) {
        for (int i = 0; i < dim; i++) {
            delete[] projMatrix[i];
        }
        delete[] projMatrix;
    }
}

void LSHIndex::initHash() {
    rndAs = new float*[S];
    rndBs = new float[S];
    
    for (int i = 0; i < S; i++) {
        rndAs[i] = new float[dim_low];
    }
    
    std::mt19937 rng(42); // Fixed seed
    std::uniform_real_distribution<float> ur(0, W);
    std::normal_distribution<float> nd;
    
    for (int j = 0; j < S; j++) {
        for (int i = 0; i < dim_low; i++) {
            rndAs[j][i] = nd(rng);
        }
        rndBs[j] = ur(rng);
    }
}

float* LSHIndex::computeHash(const float* point) {
    float* res = new float[S];
    computeHashTo(point, res);
    return res;
}

void LSHIndex::computeHashTo(const float* point, float* out_hash) {
    float low_vec[64];  // Stack buffer; dim_low <= 64
    if (dim_low > 64) return;
    projectToLowDim(point, low_vec);
    for (int i = 0; i < S; i++) {
        out_hash[i] = (innerProduct(low_vec, rndAs[i], dim_low) + rndBs[i]) / W;
    }
}

void LSHIndex::projectToLowDim(const float* vec, float* low_vec) {
    for (int j = 0; j < dim_low; j++) {
        low_vec[j] = 0.0f;
        for (int i = 0; i < dim; i++) {
            low_vec[j] += vec[i] * projMatrix[i][j];
        }
        // Normalize
        low_vec[j] /= sqrt((float)dim);
    }
}

float LSHIndex::innerProduct(const float* a, const float* b, int len) {
    float sum = 0.0f;
    for (int i = 0; i < len; i++) {
        sum += a[i] * b[i];
    }
    return sum;
}

zint LSHIndex::getZ(const float* hash_vals, int table_idx) {
    // FNV-1a style stable 64-bit hash mixing
    const uint64_t FNV_OFFSET = 14695981039346656037ULL;
    const uint64_t FNV_PRIME = 1099511628211ULL;
    uint64_t res = FNV_OFFSET;
    int start = table_idx * K;
    for (int j = 0; j < K; ++j) {
        int bucket = static_cast<int>(std::floor(hash_vals[start + j]));
        uint32_t v = static_cast<uint32_t>(bucket);
        res ^= static_cast<uint64_t>(v);
        res *= FNV_PRIME;
    }
    return static_cast<zint>(res);
}

int LSHIndex::getLLCP(zint k1, zint k2) {
    if (k1 == k2) {
        return ZINT_LEN;
    } else {
#ifdef __GNUC__
        return __builtin_clzll(k1 ^ k2);
#elif defined _MSC_VER
        return (int)_lzcnt_u64(k1 ^ k2);
#else
        // Fallback implementation
        zint diff = k1 ^ k2;
        int count = 0;
        while (diff && count < ZINT_LEN) {
            diff >>= 1;
            count++;
        }
        return ZINT_LEN - count;
#endif
    }
}

void LSHIndex::add(int oid, const float* vec) {
    // Extend arrays if needed
    if (oid >= N) {
        int old_N = N;
        N = oid + 1;
        
        // Extend hashval
        float** new_hashval = new float*[N];
        for (int i = 0; i < old_N; i++) {
            new_hashval[i] = hashval[i];
        }
        for (int i = old_N; i < N; i++) {
            new_hashval[i] = nullptr;
        }
        delete[] hashval;
        hashval = new_hashval;
        
        // Extend deleted
        deleted.resize(N, false);
    }
    
    // Compute and store hash (single alloc, no temp buffers)
    if (hashval[oid] == nullptr) {
        hashval[oid] = new float[S];
        computeHashTo(vec, hashval[oid]);
    }
    
    deleted[oid] = false;
}

void LSHIndex::addBatch(const std::vector<const float*>& vecs, const std::vector<int>& eids) {
    if (vecs.size() != eids.size()) return;
    int max_eid = -1;
    for (int eid : eids) if (eid > max_eid) max_eid = eid;
    if (max_eid >= N) {
        int old_N = N;
        N = max_eid + 1;
        float** new_hashval = new float*[N];
        for (int i = 0; i < old_N; i++) new_hashval[i] = hashval[i];
        for (int i = old_N; i < N; i++) new_hashval[i] = nullptr;
        delete[] hashval;
        hashval = new_hashval;
        deleted.resize(N, false);
    }
#pragma omp parallel for schedule(static)
    for (size_t i = 0; i < vecs.size(); i++) {
        int eid = eids[i];
        hashval[eid] = new float[S];
        computeHashTo(vecs[i], hashval[eid]);
        deleted[eid] = false;
    }
}

void LSHIndex::remove(int oid) {
    if (oid < N && !deleted[oid]) {
        deleted[oid] = true;
        deleted_count++;
    }
}

void LSHIndex::build() {
    // Count valid points
    int valid_count = 0;
    std::vector<int> valid_oids;
    for (int i = 0; i < N; i++) {
        if (!deleted[i] && hashval[i] != nullptr) {
            valid_count++;
            valid_oids.push_back(i);
        }
    }
    
    if (valid_count == 0) {
        table_size_ = 0;
        if (hashTables) {
            for (int i = 0; i < L; i++) {
                delete[] hashTables[i];
            }
            delete[] hashTables;
            hashTables = nullptr;
        }
        return;
    }
    
    // Allocate hash tables
    if (hashTables) {
        for (int i = 0; i < L; i++) {
            delete[] hashTables[i];
        }
        delete[] hashTables;
    }
    
    hashTables = new HashPair*[L];
    for (int i = 0; i < L; i++) {
        hashTables[i] = new HashPair[valid_count];
    }
    
    // Build hash tables (parallel sort)
#pragma omp parallel for schedule(static)
    for (int j = 0; j < L; j++) {
        int cnt = 0;
        for (int oid : valid_oids) {
            zint key = getZ(hashval[oid], j);
            hashTables[j][cnt++] = HashPair(key, oid);
        }
        std::sort(hashTables[j], hashTables[j] + valid_count);
    }
    
    table_size_ = valid_count;
    deleted_count = 0;
}

std::vector<int> LSHIndex::querySeeds(const float* query, int seed_count) {
    std::vector<int> seeds;
    if (N == 0 || hashTables == nullptr || table_size_ <= 0) return seeds;
    
    // Compute query hash (stack buffer, no heap alloc)
    float q_hash[64];
    if (S > 64) return seeds;
    computeHashTo(query, q_hash);
    std::vector<zint> keys(L);
    for (int j = 0; j < L; j++) {
        keys[j] = getZ(q_hash, j);
    }
    
    // Bidirectional search
    std::vector<HashPair*> lpos(L), rpos(L), qpos(L);
    std::priority_queue<PosInfo> lEntries, rEntries;
    
    for (int j = 0; j < L; j++) {
        HashPair key_pair(keys[j], -1);
        qpos[j] = std::lower_bound(hashTables[j], hashTables[j] + table_size_, key_pair);
        
        if (qpos[j] != hashTables[j]) {
            lpos[j] = qpos[j];
            --lpos[j];
            lEntries.push(PosInfo(j, getLLCP(lpos[j]->val, keys[j])));
        }
        
        rpos[j] = qpos[j];
        if (rpos[j] != hashTables[j] + table_size_) {
            rEntries.push(PosInfo(j, getLLCP(rpos[j]->val, keys[j])));
        }
    }
    
    std::unordered_set<int> visited;
    int step = 1;
    int lshUB = L * 10; // Limit search
    
    while (!(lEntries.empty() && rEntries.empty()) && seeds.size() < seed_count && visited.size() < lshUB) {
        PosInfo t;
        bool f = true; // true: left, false: right
        
        if (lEntries.empty()) f = false;
        else if (rEntries.empty()) f = true;
        else if (rEntries.top().dist > lEntries.top().dist) f = false;
        
        if (f) {
            t = lEntries.top();
            lEntries.pop();
            for (int i = 0; i < step; ++i) {
                int rid = lpos[t.id]->id;
                if (visited.find(rid) == visited.end() && !deleted[rid]) {
                    seeds.push_back(rid);
                    visited.insert(rid);
                    if (seeds.size() >= seed_count) break;
                }
                if (lpos[t.id] != hashTables[t.id]) {
                    --lpos[t.id];
                } else {
                    break;
                }
            }
            if (lpos[t.id] != hashTables[t.id] && seeds.size() < seed_count) {
                t.dist = getLLCP(lpos[t.id]->val, keys[t.id]);
                lEntries.push(t);
            }
        } else {
            t = rEntries.top();
            rEntries.pop();
            for (int i = 0; i < step; ++i) {
                int rid = rpos[t.id]->id;
                if (visited.find(rid) == visited.end() && !deleted[rid]) {
                    seeds.push_back(rid);
                    visited.insert(rid);
                    if (seeds.size() >= seed_count) break;
                }
                if (++rpos[t.id] == hashTables[t.id] + table_size_) {
                    break;
                }
            }
            if (rpos[t.id] != hashTables[t.id] + table_size_ && seeds.size() < seed_count) {
                t.dist = getLLCP(rpos[t.id]->val, keys[t.id]);
                rEntries.push(t);
            }
        }
    }
    
    return seeds;
}

void LSHIndex::rebuild(const std::vector<const float*>& all_vecs, const std::vector<int>& valid_eids) {
    if (all_vecs.size() != valid_eids.size()) {
        return;
    }
    
    // Clear old hashval array safely
    if (hashval) {
        for (int i = 0; i < N; i++) {
            if (hashval[i]) {
                delete[] hashval[i];
            }
        }
        delete[] hashval;
        hashval = nullptr;
    }
    
    // Determine new N by max eid
    int max_eid = -1;
    for (int eid : valid_eids) {
        if (eid > max_eid) max_eid = eid;
    }
    N = (max_eid >= 0) ? (max_eid + 1) : 0;
    
    hashval = new float*[N];
    for (int i = 0; i < N; ++i) {
        hashval[i] = nullptr;
    }
    deleted.clear();
    deleted.resize(N, false);
    deleted_count = 0;
    
    // Fill hashval for each valid_eid using corresponding all_vecs entry
    for (size_t idx = 0; idx < valid_eids.size(); ++idx) {
        int eid = valid_eids[idx];
        if (eid >= 0 && eid < N) {
            hashval[eid] = new float[S];
            computeHashTo(all_vecs[idx], hashval[eid]);
            deleted[eid] = false;
        }
    }
    
    // Rebuild tables
    build();
}
