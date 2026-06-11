#pragma once

#include <vector>
#include <map>
#include <cstdint>
#include <random>
#include <algorithm>
#include <cmath>
#include <cfloat>

// zint type for hash keys
using zint = uint64_t;
const int ZINT_LEN = sizeof(zint) * 8;

// Hash pair for sorted array
struct HashPair {
    zint val;
    int id;
    HashPair() = default;
    HashPair(zint v_, int id_) : val(v_), id(id_) {}
    bool operator < (const HashPair& rhs) const {
        return val < rhs.val;
    }
};

// Position info for bidirectional search
struct PosInfo {
    int id = -1;
    int dist = -1;
    bool operator < (const PosInfo& rhs) const {
        return dist < rhs.dist;
    }
    PosInfo() {}
    PosInfo(int id_, int l_) : id(id_), dist(l_) {}
};

// Lightweight LSH index for second-level entries
class LSHIndex {
public:
    int L;              // Number of hash tables
    int K;              // Number of hash functions per table
    int S;              // Total hash functions (L * K)
    int dim;            // Original dimension
    int dim_low;        // Low dimension after random projection
    int N;              // Number of points
    float W;            // Hash width parameter
    int u;              // Bits per hash value
    
    // Hash parameters
    float** rndAs;      // Random projection vectors (S x dim_low)
    float* rndBs;       // Random offsets (S)
    
    // Hash values for all points (N x S)
    float** hashval;
    
    // Hash tables (L tables, each sorted array)
    HashPair** hashTables;
    int table_size_;  // Number of entries in hashTables (set at build time)
    
    // Random projection matrix (dim x dim_low)
    float** projMatrix;
    
    // Lazy delete tracking
    std::vector<bool> deleted;
    int deleted_count;
    static const int REBUILD_THRESHOLD = 50; // Rebuild when 50% deleted (avoid frequent rebuild)
    
    // Get deleted count (for external access)
    int getDeletedCount() const { return deleted_count; }
    
    // Get N (for debug/alignment check)
    int getN() const { return N; }
    
public:
    LSHIndex(int L_, int K_, int dim_, int dim_low_ = 32, float W_ = 1.0f);
    ~LSHIndex();
    
    // Initialize hash parameters
    void initHash();
    
    // Compute hash value for a point (allocates; avoid in hot path)
    float* computeHash(const float* point);
    
    // Compute hash into pre-allocated buffer (no heap allocation)
    void computeHashTo(const float* point, float* out_hash);
    
    // Convert hash values to zint key
    zint getZ(const float* hash_vals, int table_idx);
    
    // Get longest common prefix (for sorting)
    int getLLCP(zint k1, zint k2);
    
    // Add a point to LSH index
    void add(int oid, const float* vec);
    
    // Batch add (parallel), use after reserve
    void addBatch(const std::vector<const float*>& vecs, const std::vector<int>& eids);
    
    // Remove a point (lazy delete)
    void remove(int oid);
    
    // Build index after adding all points
    void build();
    
    // Query seeds for a query point
    std::vector<int> querySeeds(const float* query, int seed_count);
    
    // Rebuild index (for lazy delete)
    // Note: valid_eids are entry indices in entries_sec (eid), not global oid
    void rebuild(const std::vector<const float*>& all_vecs, const std::vector<int>& valid_eids);
    
private:
    // Compute inner product
    float innerProduct(const float* a, const float* b, int len);
    
    // Random projection
    void projectToLowDim(const float* vec, float* low_vec);
};
