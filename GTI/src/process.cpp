#include "process.h"
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <random>
#include <algorithm>

// Build GTI
void build(GTI *&gti, unsigned capacity_up_i, unsigned capacity_up_l, unsigned m, Objects *data, float &time_index)
{
    std::cout << "========== Build GTI ==========" << std::endl;
    std::cout << "Graph M: " << m << std::endl;
    auto s = std::chrono::high_resolution_clock::now();
    gti->buildGTI(capacity_up_i, capacity_up_l, m, data);
    auto e = std::chrono::high_resolution_clock::now();
    std::chrono::duration<float> diff = e - s;
    time_index = diff.count();
    std::cout << "Time of index construction: " << time_index << "s" << std::endl;
    gti->getTreeSize();
    // double sizeInMB = gti->tree_size / (1024.0 * 1024.0);
    // std::cout << "Size of tree: " << sizeInMB << std::endl;
}

// Approximate k-NN search
void searchApproKnn(Objects *query, GTI *gti, unsigned k, unsigned l, char *res_file, char *gt_file, float time_index)
{
    // Load ground truth
    GroundTruth *gt = new GroundTruth();
    gt->loadGT(gt_file);
    gt->num = 100;

    // Query using GTI
    std::cout << "========== Search GTI ==========" << std::endl;
    query->num = 100;
    printf("query->num: %d\n", query->num);
    NN results(query->num);
    auto s = std::chrono::high_resolution_clock::now();
    for (unsigned i = 0; i < query->num; i++)
        gti->search(query->vecs[i].data(), l, k, results[i]); // Search GTI
    auto e = std::chrono::high_resolution_clock::now();
    std::chrono::duration<float> diff = e - s;
    float time_search = diff.count();
    std::cout << "Time of search: " << time_search / query->num << "s" << std::endl;

    float recall = gt->getRecall(results, k); // Load ground truth
    std::cout << "Search recall: " << recall << std::endl;

    // Save results in file
    std::cout << "========== Save results ==========" << std::endl;
    std::stringstream ss;
    ss << res_file << "cost_" << k << "_" << l << ".txt";
    std::string filename = ss.str();
    std::stringstream ss2;
    ss2 << res_file << "model";
    std::string modelname = ss2.str();
    // gti->index_hnsw->SaveModel(modelname);
    FILE *fcost = fopen(filename.c_str(), "w");
    if (!fcost)
    {
        std::cerr << "Error opening file: " << filename << std::endl;
        return;
    }
    fprintf(fcost, "%d-NN Search\n", k);
    fprintf(fcost, "Time of index construction: %f\n", time_index);
    // double sizeInMB = gti->tree_size / (1024.0 * 1024.0);
    // fprintf(fcost, "Size of tree: %f\n", sizeInMB);
    fprintf(fcost, "Search time: %f\n", time_search / query->num);
    fprintf(fcost, "Search recall: %f\n", recall);
    fflush(fcost);
    fclose(fcost);

    std::cout << "Results saved to " << filename << std::endl;
}

// Exact k-NN search
void searchExactKnn(Objects *query, GTI *gti, unsigned k, unsigned l, char *res_file, float time_index)
{
    // Query using GTI
    std::cout << "========== Exact k-NN Search Using GTI ==========" << std::endl;
    query->num = 100;
    printf("query->num: %d\n", query->num);
    NN results(query->num);
    std::chrono::duration<float> diff = std::chrono::duration<double>::zero();
    std::priority_queue<Neighbor, std::vector<Neighbor>, std::less<Neighbor>> res;
    for (unsigned i = 0; i < query->num; i++)
    {
        auto s = std::chrono::high_resolution_clock::now();
        gti->searchExactKnn(query->vecs[i].data(), l, k, results[i], res); // Search GTI
        auto e = std::chrono::high_resolution_clock::now();
        diff += e - s;

        unsigned j = 0;
        while (!res.empty())
        {
            Neighbor nn;
            nn.id = res.top().id;
            results[i][k - 1 - j] = nn;
            res.pop();
        }
    }
    float time_search = diff.count();
    std::cout << "Time of search: " << time_search / query->num << "s" << std::endl;

    // float recall = gt->getRecall(results, k); // Load ground truth
    // std::cout << "Search recall: " << recall << std::endl;

    // Save results in file
    std::cout << "========== Save results ==========" << std::endl;
    std::stringstream ss;
    ss << res_file << "cost_" << k << "_" << l << ".txt";
    std::string filename = ss.str();
    FILE *fcost = fopen(filename.c_str(), "w");
    if (!fcost)
    {
        std::cerr << "Error opening file: " << filename << std::endl;
    }
    fprintf(fcost, "%d-NN Search\n", k);
    // fprintf(fcost, "\nIndex size: %f\n", index_size);
    fprintf(fcost, "Time of index construction: %f\n", time_index);
    fprintf(fcost, "Search time: %f\n", time_search / query->num);
    // fprintf(fcost, "Search recall: %f\n", recall);
    fflush(fcost);
    fclose(fcost);

    std::cout << "Results saved to " << filename << std::endl;
}

// Exact range query
void searchExactRange(Objects *query, GTI *gti, float r, char *res_file, float time_index)
{
    // Query using GTI
    std::cout << "========== Exact Range Search Using GTI ==========" << std::endl;
    query->num = 100;
    printf("query->num: %d\n", query->num);
    NN results(query->num);
    auto s = std::chrono::high_resolution_clock::now();
    for (unsigned i = 0; i < query->num; i++)
    {
        gti->searchTreeRange(query->vecs[i].data(), r, results[i]); // Search GTI
    }
    auto e = std::chrono::high_resolution_clock::now();
    std::chrono::duration<float> diff = e - s;
    float time_search = diff.count();
    std::cout << "Time of search: " << time_search / query->num << "s" << std::endl;

    // Save results in file
    std::cout << "========== Save results ==========" << std::endl;
    std::stringstream ss;
    ss << res_file << "cost_" << r << ".txt";
    std::string filename = ss.str();
    FILE *fcost = fopen(filename.c_str(), "w");
    if (!fcost)
    {
        std::cerr << "Error opening file: " << filename << std::endl;
    }
    fprintf(fcost, "Range Search, radius = %f\n", r);
    // fprintf(fcost, "\nIndex size: %f\n", index_size);
    for (unsigned i = 0; i < query->num; i++)
        fprintf(fcost, "%d ", int(results[i].size()));
    fprintf(fcost, "\n");
    fprintf(fcost, "Time of index construction: %f\n", time_index);
    fprintf(fcost, "Search time: %f\n", time_search / query->num);
    fflush(fcost);
    fclose(fcost);

    std::cout << "Results saved to " << filename << std::endl;
}

// Update
void update(Objects *data, GTI *&gti, Objects *query, char *res_file, char *gt_file, float time_index)
{
    std::cout << "========== Update ==========" << std::endl;

    // Load ground truth
    GroundTruth *gt = new GroundTruth();
    gt->loadGT(gt_file);
    gt->num = 100;

    // Update scale: 默认 1% 数据量；GTI_UPDATE_RATIO 可覆盖（如 0.005=0.5%）
    double update_ratio = 0.01;
    if (const char *s = std::getenv("GTI_UPDATE_RATIO"))
        update_ratio = std::strtod(s, nullptr);
    unsigned delete_data_size = (unsigned)std::max(1.0, data->num * update_ratio);
    // Interleave queries during updates (simulate concurrent queries)
    unsigned chunk_size = std::max(1u, delete_data_size / 10); // 10 批
    const unsigned k = 10;
    unsigned l = 60;  // 图返回候选数，增大可提升召回；GTI_SEARCH_L 可覆盖
    if (const char *s = std::getenv("GTI_SEARCH_L"))
        l = (unsigned)std::strtoul(s, nullptr, 10);
    std::cout << "Search L: " << l << std::endl;

    // Prepare update objects.
    // 对于插入实验，我们直接从 base 数据集中取前 update_n 个向量作为更新对象。
    // 这里仅做插入（insert-only），不会调用 deleteGTI，因此不会破坏原始数据分布。
    Objects *update_data = new Objects();
    update_data->dim = data->dim;
    update_data->type = data->type;
    update_data->num = delete_data_size;
    update_data->vecs.assign(data->vecs.begin(), data->vecs.begin() + delete_data_size);

    // CSV log: update curve (phase, updated_count, avg_update_s_per_item, avg_search_s_per_query, recall)
    std::stringstream csv_ss;
    csv_ss << res_file << "update_curve_k" << k << "_l" << l << "_ratio" << std::fixed << std::setprecision(3) << update_ratio << ".csv";
    std::string csv_name = csv_ss.str();
    std::ofstream csv(csv_name, std::ios::out);
    csv << "phase,updated,avg_update_s_per_item,avg_search_s_per_query,recall\n";

    auto run_query_and_log = [&](const std::string &phase, unsigned updated_cnt, float update_time_s_total) {
        std::cout << "========== Search GTI ==========" << std::endl;
        query->num = 100;
        printf("query->num: %d\n", query->num);
        NN results(query->num);
        auto qs = std::chrono::high_resolution_clock::now();
        for (unsigned i = 0; i < query->num; i++)
            gti->search(query->vecs[i].data(), l, k, results[i]); // Search GTI
        auto qe = std::chrono::high_resolution_clock::now();
        std::chrono::duration<float> qdiff = qe - qs;
        float time_search = qdiff.count();
        std::cout << "Time of search: " << time_search / query->num << "s" << std::endl;

        float recall = gt->getRecall(results, k);
        std::cout << "Search recall: " << recall << std::endl;

        float avg_update = (updated_cnt == 0) ? 0.0f : (update_time_s_total / updated_cnt);
        float avg_search = time_search / query->num;
        csv << phase << "," << updated_cnt << "," << avg_update << "," << avg_search << "," << recall << "\n";
        csv.flush();
#if defined(GTI_USE_SHG)
        if (const char *v = std::getenv("GTI_SHG_VERBOSE_LEVELSKIP"); v && v[0] == '1') {
            gti->printAndResetLevelsSkipStats();
        }
#endif
    };

    // Phase 1: insert (chunked), interleave queries
    float total_insert_s = 0.0f;
    std::cout << "Update setting: ratio=" << update_ratio << ", update_n=" << delete_data_size
              << ", chunk_size=" << chunk_size << std::endl;
    for (unsigned start = 0; start < delete_data_size; start += chunk_size)
    {
        unsigned end = std::min(delete_data_size, start + chunk_size);
        Objects chunk;
        chunk.dim = data->dim;
        chunk.type = data->type;
        chunk.num = end - start;
        chunk.vecs.assign(update_data->vecs.begin() + start, update_data->vecs.begin() + end);

        auto s = std::chrono::high_resolution_clock::now();
        gti->insertGTI(&chunk);
        auto e = std::chrono::high_resolution_clock::now();
        std::chrono::duration<float> diff = e - s;
        total_insert_s += diff.count();

        run_query_and_log("insert", end, total_insert_s);
    }
    std::cout << "Insert avg time: " << total_insert_s / delete_data_size << "s" << std::endl;

#if defined(GTI_USE_SHG)
    // D: optional rebuild Shortcuts after Phase 1 insert (GTI_SHG_REBUILD_AFTER_INSERT=1)
    if (const char *s = std::getenv("GTI_SHG_REBUILD_AFTER_INSERT"); s && s[0] == '1') {
        auto t0 = std::chrono::high_resolution_clock::now();
        gti->rebuildShortcuts();
        auto t1 = std::chrono::high_resolution_clock::now();
        std::cout << "[D] rebuildShortcuts elapsed: " << std::chrono::duration<float>(t1 - t0).count() << "s" << std::endl;
    }
#endif

    // Phase 2: chunked delete with rebuild threshold
    unsigned delete_cap = delete_data_size;
    if (const char *s = std::getenv("GTI_UPDATE_DELETE_N"))
        delete_cap = (unsigned)std::strtoul(s, nullptr, 10);
    unsigned delete_count = std::min(delete_cap, delete_data_size);
    // chunk_size: 插入时 chunk=1000 有召回下降，删除可设 GTI_DELETE_CHUNK_SIZE 或默认 delete_count/5
    // GTI_DELETE_DIRECT=1: 直接删除一批次，chunk=delete_count
    unsigned delete_chunk_size = std::max(1u, delete_count / 5);
    if (std::getenv("GTI_DELETE_DIRECT") != nullptr && std::strcmp(std::getenv("GTI_DELETE_DIRECT"), "1") == 0)
        delete_chunk_size = delete_count;
    else if (const char *s = std::getenv("GTI_DELETE_CHUNK_SIZE"))
        delete_chunk_size = (unsigned)std::strtoul(s, nullptr, 10);
    unsigned rebuild_threshold = delete_count / 2;
    if (const char *s = std::getenv("GTI_REBUILD_THRESHOLD"))
        rebuild_threshold = (unsigned)std::strtoul(s, nullptr, 10);
    // GTI_PATCH_DELETE_ONLY=1: 纯 Wolverine patchDelete，每批都真删，无 Lazy delete
    if (std::getenv("GTI_PATCH_DELETE_ONLY") != nullptr && std::strcmp(std::getenv("GTI_PATCH_DELETE_ONLY"), "1") == 0)
        rebuild_threshold = 0;
    float total_delete_s = 0.0f;
    bool delete_random = (std::getenv("GTI_DELETE_RANDOM") != nullptr && std::strcmp(std::getenv("GTI_DELETE_RANDOM"), "1") == 0);
    std::vector<unsigned> delete_oid_order;  // 删除顺序：随机时为打乱后的 oid，否则为 0,1,2,...
    if (delete_count > 0)
    {
        delete_oid_order.resize(delete_data_size);
        for (unsigned i = 0; i < delete_data_size; i++)
            delete_oid_order[i] = i;
        if (delete_random)
        {
            std::mt19937 rng(42);
            std::shuffle(delete_oid_order.begin(), delete_oid_order.end(), rng);
            bool patch_only = (rebuild_threshold == 0);
#if defined(GTI_USE_SHG)
            std::cout << "========== Chunked delete " << delete_count << " items (RANDOM oids, chunk=" << delete_chunk_size
                      << ", rebuild_threshold=" << rebuild_threshold << (patch_only ? ", MARK_DELETE_ONLY" : "") << ") ==========" << std::endl;
#else
            std::cout << "========== Chunked delete " << delete_count << " items (RANDOM oids, chunk=" << delete_chunk_size
                      << ", rebuild_threshold=" << rebuild_threshold << (patch_only ? ", PATCH_DELETE_ONLY" : "") << ") ==========" << std::endl;
#endif
        }
        else
        {
            bool patch_only = (rebuild_threshold == 0);
#if defined(GTI_USE_SHG)
            std::cout << "========== Chunked delete " << delete_count << " items (chunk=" << delete_chunk_size
                      << ", rebuild_threshold=" << rebuild_threshold << (patch_only ? ", MARK_DELETE_ONLY" : "") << ") ==========" << std::endl;
#else
            std::cout << "========== Chunked delete " << delete_count << " items (chunk=" << delete_chunk_size
                      << ", rebuild_threshold=" << rebuild_threshold << (patch_only ? ", PATCH_DELETE_ONLY" : "") << ") ==========" << std::endl;
#endif
        }
        unsigned accumulated_deleted = 0;
        unsigned last_rebuild_at = 0;
        for (unsigned start = 0; start < delete_count; start += delete_chunk_size)
        {
            unsigned end = std::min(delete_count, start + delete_chunk_size);
            unsigned chunk_n = end - start;
            accumulated_deleted = end;

            bool do_rebuild = (accumulated_deleted > rebuild_threshold);
            bool patch_delete_only = (rebuild_threshold == 0);
            if (do_rebuild)
            {
                unsigned rebuild_start = last_rebuild_at;
                unsigned rebuild_n = accumulated_deleted - rebuild_start;
                for (unsigned i = rebuild_start; i < accumulated_deleted; i++)
                    gti->lazy_deleted_oids.erase(delete_oid_order[i]);

                Objects all_delete_obj;
                all_delete_obj.dim = update_data->dim;
                all_delete_obj.type = update_data->type;
                all_delete_obj.num = rebuild_n;
                for (unsigned i = rebuild_start; i < accumulated_deleted; i++)
                    all_delete_obj.vecs.push_back(update_data->vecs[delete_oid_order[i]]);

#if defined(GTI_USE_SHG)
                const char *phase_label = patch_delete_only ? "MarkDelete" : "Rebuild";
                const char *csv_phase = patch_delete_only ? "delete_mark" : "delete_rebuild";
#else
                const char *phase_label = patch_delete_only ? "PatchDelete" : "Rebuild";
                const char *csv_phase = patch_delete_only ? "delete_patch" : "delete_rebuild";
#endif
                std::cout << "  " << phase_label << " " << rebuild_n << " items (total " << accumulated_deleted << ") ... " << std::flush;
                auto ds = std::chrono::high_resolution_clock::now();
                gti->deleteGTI(&all_delete_obj, true);
                auto de = std::chrono::high_resolution_clock::now();
                std::chrono::duration<float> ddiff = de - ds;
                total_delete_s += ddiff.count();
                std::cout << "total=" << ddiff.count() << "s"
                          << " (graph_update=" << gti->last_graph_update_s << "s, rebuild=" << gti->last_rebuild_s << "s)" << std::endl;
                run_query_and_log(csv_phase, accumulated_deleted, total_delete_s);
                last_rebuild_at = accumulated_deleted;
            }
            else
            {
                std::cout << "  Lazy delete " << chunk_n << " (total " << accumulated_deleted << ") ... " << std::flush;
                std::vector<unsigned> chunk_oids;
                for (unsigned i = start; i < end; i++)
                    chunk_oids.push_back(delete_oid_order[i]);
                auto ds = std::chrono::high_resolution_clock::now();
                gti->deleteGTI_lazyOids(chunk_oids);
                auto de = std::chrono::high_resolution_clock::now();
                std::chrono::duration<float> ddiff = de - ds;
                total_delete_s += ddiff.count();
                std::cout << ddiff.count() << "s" << std::endl;
                run_query_and_log("delete_no_rebuild", accumulated_deleted, total_delete_s);
            }
        }
        // 若最后仍有 lazy 未重建，做一次最终 rebuild
        // SHG markDelete 已在每批完成，lazy_deleted_oids 仅用于搜索过滤，不需 final rebuild
#if defined(GTI_USE_SHG)
        bool need_final_rebuild = !gti->lazy_deleted_oids.empty() && (rebuild_threshold > 0);
#else
        bool need_final_rebuild = !gti->lazy_deleted_oids.empty();
#endif
        if (need_final_rebuild)
        {
            std::vector<unsigned> final_oids(gti->lazy_deleted_oids.begin(), gti->lazy_deleted_oids.end());
            std::sort(final_oids.begin(), final_oids.end());  // 排序以便稳定取 vec
            Objects final_obj;
            final_obj.dim = update_data->dim;
            final_obj.type = update_data->type;
            final_obj.num = final_oids.size();
            for (unsigned oid : final_oids)
                final_obj.vecs.push_back(update_data->vecs[oid]);

            std::cout << "  Final rebuild " << final_oids.size() << " items ... " << std::flush;
            auto ds = std::chrono::high_resolution_clock::now();
            gti->deleteGTI(&final_obj, true);
            auto de = std::chrono::high_resolution_clock::now();
            std::chrono::duration<float> ddiff = de - ds;
            total_delete_s += ddiff.count();
            std::cout << "total=" << ddiff.count() << "s (graph_update=" << gti->last_graph_update_s
                      << "s, rebuild=" << gti->last_rebuild_s << "s)" << std::endl;
            run_query_and_log("delete_rebuild", delete_count, total_delete_s);
        }
        std::cout << "Delete total time: " << total_delete_s << "s, avg per item: " << total_delete_s / delete_count << "s" << std::endl;
    }

    // Save summary file (keep old naming style but make it explicit that it's update)
    std::cout << "========== Save results ==========" << std::endl;
    std::stringstream ss;
    ss << res_file << "update_summary_k" << k << "_l" << l << "_ratio" << std::fixed << std::setprecision(3) << update_ratio << ".txt";
    std::string filename = ss.str();
    FILE *fcost = fopen(filename.c_str(), "w");
    if (!fcost)
    {
        std::cerr << "Error opening file: " << filename << std::endl;
        return;
    }
    fprintf(fcost, "Update experiment (chunked)\n");
    fprintf(fcost, "Time of index construction: %f\n", time_index);
    fprintf(fcost, "Update ratio: %f\n", update_ratio);
    fprintf(fcost, "Insert n: %u\n", delete_data_size);
    fprintf(fcost, "Delete n: %u\n", delete_count);
    fprintf(fcost, "Insert chunk size: %u\n", chunk_size);
    fprintf(fcost, "Delete chunk size: %u\n", delete_count > 0 ? (unsigned)delete_chunk_size : 0u);
    fprintf(fcost, "Rebuild threshold: %u\n", delete_count > 0 ? rebuild_threshold : 0u);
    if (delete_count > 0 && rebuild_threshold == 0)
        fprintf(fcost, "Delete strategy: patch_delete_only\n");
    fprintf(fcost, "Insert avg time (s/item): %f\n", total_insert_s / delete_data_size);
    if (delete_count > 0)
        fprintf(fcost, "Delete avg time (s/item): %f\n", total_delete_s / delete_count);
    fprintf(fcost, "Curve CSV: %s\n", csv_name.c_str());
    fflush(fcost);
    fclose(fcost);

    std::cout << "Results saved to " << filename << std::endl;
    std::cout << "Curve saved to " << csv_name << std::endl;
}

// Update OPS: 分批插入+分批删除，每批次输出 recall,search_OPS,delete_OPS,insert_OPS（避免一次性插入卡住）
void updateOPS(Objects *data, GTI *&gti, Objects *query, char *res_file, char *gt_file, float time_index)
{
    std::cout << "========== Update OPS (chunked insert+delete) ==========" << std::endl;

    double update_ratio = 0.01;
    if (const char *s = std::getenv("GTI_UPDATE_RATIO"))
        update_ratio = std::strtod(s, nullptr);

    unsigned update_n = (unsigned)std::max(1.0, data->num * update_ratio);
    unsigned insert_chunk = std::max(1u, update_n / 10);  // 默认 10 批，与 run.log 一致
    if (const char *s = std::getenv("GTI_INSERT_CHUNK_SIZE"))
        insert_chunk = (unsigned)std::strtoul(s, nullptr, 10);
    unsigned delete_chunk = std::max(1u, update_n / 5);   // 默认 5 批删除
    if (const char *s = std::getenv("GTI_DELETE_CHUNK_SIZE"))
        delete_chunk = (unsigned)std::strtoul(s, nullptr, 10);

    const unsigned k = 10;
    unsigned l = 60;
    if (const char *s = std::getenv("GTI_SEARCH_L"))
        l = (unsigned)std::strtoul(s, nullptr, 10);

    unsigned rebuild_threshold = update_n / 2;
    if (const char *s = std::getenv("GTI_REBUILD_THRESHOLD"))
        rebuild_threshold = (unsigned)std::strtoul(s, nullptr, 10);
    bool patch_only = (std::getenv("GTI_PATCH_DELETE_ONLY") != nullptr && std::strcmp(std::getenv("GTI_PATCH_DELETE_ONLY"), "1") == 0);
    if (patch_only) rebuild_threshold = 0;

    std::cout << "update_n: " << update_n << " insert_chunk: " << insert_chunk << " delete_chunk: " << delete_chunk
              << " rebuild_threshold: " << rebuild_threshold << (patch_only ? " (patch_only)" : "") << std::endl;

    GroundTruth *gt = new GroundTruth();
    gt->loadGT(gt_file);
    gt->num = 100;

    std::string csv_path = std::string(res_file) + "ops_k" + std::to_string(k) + "_l" + std::to_string(l) + ".csv";
    std::ofstream csv(csv_path);
    csv << "recall,search_OPS,delete_OPS,insert_OPS\n";

    auto run_search = [&]() {
        query->num = 100;
        NN results(query->num);
        auto qs = std::chrono::high_resolution_clock::now();
        for (unsigned i = 0; i < query->num; i++)
            gti->search(query->vecs[i].data(), l, k, results[i]);
        auto qe = std::chrono::high_resolution_clock::now();
        float st = std::chrono::duration<float>(qe - qs).count();
        return std::make_pair(gt->getRecall(results, k), (st > 0) ? (query->num / st) : 0.0f);
    };

    float avg_insert_OPS = 0;
    unsigned insert_batches = 0;

    // Phase 1: 分批插入（每批后 search，输出 insert_OPS）
    std::cout << "========== Chunked insert " << update_n << " (chunk=" << insert_chunk << ") ==========" << std::endl;
    Objects *update_data = new Objects();
    update_data->dim = data->dim;
    update_data->type = data->type;
    update_data->num = update_n;
    update_data->vecs.assign(data->vecs.begin(), data->vecs.begin() + update_n);

    for (unsigned start = 0; start < update_n; start += insert_chunk)
    {
        unsigned end = std::min(update_n, start + insert_chunk);
        unsigned chunk_n = end - start;
        Objects chunk;
        chunk.dim = data->dim;
        chunk.type = data->type;
        chunk.num = chunk_n;
        chunk.vecs.assign(update_data->vecs.begin() + start, update_data->vecs.begin() + end);

        auto ins_s = std::chrono::high_resolution_clock::now();
        gti->insertGTI(&chunk);
        auto ins_e = std::chrono::high_resolution_clock::now();
        float ins_t = std::chrono::duration<float>(ins_e - ins_s).count();
        float batch_insert_OPS = (ins_t > 0) ? (chunk_n / ins_t) : 0;
        avg_insert_OPS += batch_insert_OPS;
        insert_batches++;

        auto sr = run_search();
        std::cout << "  Insert " << chunk_n << " in " << ins_t << "s, insert_OPS=" << batch_insert_OPS
                  << " | recall=" << sr.first << " search_OPS=" << sr.second << std::endl;
        csv << sr.first << "," << sr.second << ",0," << batch_insert_OPS << "\n";
        csv.flush();
    }
    avg_insert_OPS = (insert_batches > 0) ? (avg_insert_OPS / insert_batches) : 0;
    std::cout << "Insert avg OPS: " << avg_insert_OPS << std::endl;
    delete update_data;

    // Phase 2: 分批删除（每批后 search，输出 delete_OPS）
    std::vector<unsigned> delete_oid_order(update_n);
    for (unsigned i = 0; i < update_n; i++) delete_oid_order[i] = i;
    std::mt19937 rng(100);
    std::shuffle(delete_oid_order.begin(), delete_oid_order.end(), rng);

    std::cout << "========== Chunked delete " << update_n << " (chunk=" << delete_chunk << ") ==========" << std::endl;
    for (unsigned start = 0; start < update_n; start += delete_chunk)
    {
        unsigned end = std::min(update_n, start + delete_chunk);
        unsigned chunk_n = end - start;

        std::vector<unsigned> chunk_oids(delete_oid_order.begin() + start, delete_oid_order.begin() + end);
        Objects delete_obj;
        delete_obj.dim = data->dim;
        delete_obj.type = data->type;
        delete_obj.num = chunk_n;
        for (unsigned oid : chunk_oids) delete_obj.vecs.push_back(data->vecs[oid]);

        float delete_time = 0;
        unsigned actual_deleted = chunk_n;

        if (patch_only)
        {
            auto ds = std::chrono::high_resolution_clock::now();
            gti->deleteGTI(&delete_obj, true);
            auto de = std::chrono::high_resolution_clock::now();
            delete_time = std::chrono::duration<float>(de - ds).count();
        }
        else
        {
            // lazy：只做标记，不做中途 rebuild（与 run.log 一致，避免 n2 部分 rebuild 段错误）
            auto ds = std::chrono::high_resolution_clock::now();
            gti->deleteGTI_lazyOids(chunk_oids);
            auto de = std::chrono::high_resolution_clock::now();
            delete_time = std::chrono::duration<float>(de - ds).count();
        }

        float delete_OPS = (delete_time > 0) ? (actual_deleted / delete_time) : 0;
        auto sr = run_search();
        std::cout << "  Delete " << actual_deleted << " in " << delete_time << "s, delete_OPS=" << delete_OPS
                  << " | recall=" << sr.first << " search_OPS=" << sr.second << std::endl;
        csv << sr.first << "," << sr.second << "," << delete_OPS << "," << avg_insert_OPS << "\n";
        csv.flush();
    }

    // lazy 策略：Final rebuild（与 run.log 一致），测量 rebuild_OPS
    if (!patch_only && !gti->lazy_deleted_oids.empty())
    {
        std::vector<unsigned> final_oids(gti->lazy_deleted_oids.begin(), gti->lazy_deleted_oids.end());
        std::sort(final_oids.begin(), final_oids.end());
        Objects final_obj;
        final_obj.dim = data->dim;
        final_obj.type = data->type;
        final_obj.num = final_oids.size();
        for (unsigned oid : final_oids) final_obj.vecs.push_back(data->vecs[oid]);

        std::cout << "  Final rebuild " << final_oids.size() << " items ... " << std::flush;
        auto ds = std::chrono::high_resolution_clock::now();
        gti->deleteGTI(&final_obj, true);
        auto de = std::chrono::high_resolution_clock::now();
        float rebuild_time = std::chrono::duration<float>(de - ds).count();
        float graph_update_OPS = (gti->last_graph_update_s > 0) ? (final_oids.size() / gti->last_graph_update_s) : 0;
        float rebuild_OPS_val = (gti->last_rebuild_s > 0) ? (final_oids.size() / gti->last_rebuild_s) : 0;
        std::cout << "total=" << rebuild_time << "s"
                  << " (graph_update=" << gti->last_graph_update_s << "s, rebuild=" << gti->last_rebuild_s << "s)"
                  << " graph_update_OPS=" << graph_update_OPS << " rebuild_OPS=" << rebuild_OPS_val << std::endl;

        auto sr = run_search();
        float delete_OPS = (rebuild_time > 0) ? (final_oids.size() / rebuild_time) : 0;
        csv << sr.first << "," << sr.second << "," << delete_OPS << "," << avg_insert_OPS << "\n";
        csv.flush();
    }

    csv.close();
    delete gt;
    std::cout << "OPS results saved to " << csv_path << std::endl;
}