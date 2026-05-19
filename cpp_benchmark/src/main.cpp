// Benchmark application — includes and exercises all seven header-heavy dependencies.
// Links 30 translation units, each pulling in the full set of dep headers,
// to maximise parallel file-system pressure during build.

// Boost
#include <boost/algorithm/string.hpp>
#include <boost/lexical_cast.hpp>
#include <boost/container/flat_map.hpp>

// Eigen (header-only linear algebra)
#include <Eigen/Dense>
#include <Eigen/Sparse>

// {fmt}
#include <fmt/format.h>
#include <fmt/ranges.h>
#include <fmt/chrono.h>

// spdlog
#include <spdlog/spdlog.h>
#include <spdlog/sinks/stdout_color_sinks.h>

// nlohmann/json
#include <nlohmann/json.hpp>

// abseil
#include <absl/strings/str_cat.h>
#include <absl/strings/str_join.h>
#include <absl/strings/str_split.h>

// range-v3
#include <range/v3/view/filter.hpp>
#include <range/v3/view/transform.hpp>
#include <range/v3/view/iota.hpp>
#include <range/v3/algorithm/for_each.hpp>
#include <range/v3/to_container.hpp>

#include "module_01.h"
#include "module_02.h"
#include "module_03.h"
#include "module_04.h"
#include "module_05.h"
#include "module_06.h"
#include "module_07.h"
#include "module_08.h"
#include "module_09.h"
#include "module_10.h"
#include "module_11.h"
#include "module_12.h"
#include "module_13.h"
#include "module_14.h"
#include "module_15.h"
#include "module_16.h"
#include "module_17.h"
#include "module_18.h"
#include "module_19.h"
#include "module_20.h"
#include "module_21.h"
#include "module_22.h"
#include "module_23.h"
#include "module_24.h"
#include "module_25.h"
#include "module_26.h"
#include "module_27.h"
#include "module_28.h"
#include "module_29.h"
#include "module_30.h"

#include <vector>
#include <string>

int main()
{
    auto logger = spdlog::stdout_color_mt("benchmark");
    logger->info("Starting benchmark_app ({} modules)", 30);

    // Call every module so the linker keeps all translation units
    int seed = 7;
    int total = 0;
    total += module_01_compute(seed); total += module_02_compute(seed);
    total += module_03_compute(seed); total += module_04_compute(seed);
    total += module_05_compute(seed); total += module_06_compute(seed);
    total += module_07_compute(seed); total += module_08_compute(seed);
    total += module_09_compute(seed); total += module_10_compute(seed);
    total += module_11_compute(seed); total += module_12_compute(seed);
    total += module_13_compute(seed); total += module_14_compute(seed);
    total += module_15_compute(seed); total += module_16_compute(seed);
    total += module_17_compute(seed); total += module_18_compute(seed);
    total += module_19_compute(seed); total += module_20_compute(seed);
    total += module_21_compute(seed); total += module_22_compute(seed);
    total += module_23_compute(seed); total += module_24_compute(seed);
    total += module_25_compute(seed); total += module_26_compute(seed);
    total += module_27_compute(seed); total += module_28_compute(seed);
    total += module_29_compute(seed); total += module_30_compute(seed);

    logger->info("All 30 modules computed. Checksum: {}", total);

    // --- fmt ---
    std::string header = fmt::format("Loaded {:d} dependencies across {:d} TUs", 7, 31);
    logger->info("{}", header);

    // --- nlohmann/json ---
    nlohmann::json meta = {
        {"app", "benchmark_app"},
        {"translation_units", 31},
        {"deps", {"boost", "eigen", "fmt", "spdlog", "nlohmann_json", "abseil", "range-v3"}}
    };
    logger->info("metadata: {}", meta.dump());

    // --- Eigen ---
    Eigen::Matrix4d mat = Eigen::Matrix4d::Random();
    Eigen::Matrix4d result = mat * mat.transpose();
    logger->info("Eigen: 4x4 product norm = {:.6f}", result.norm());

    // --- Boost ---
    std::string sentence = "Hello From Boost Algorithm";
    boost::algorithm::to_lower(sentence);
    std::vector<std::string> words;
    boost::algorithm::split(words, sentence, boost::algorithm::is_space(),
                            boost::algorithm::token_compress_on);
    boost::container::flat_map<std::string, int> freq;
    for (const auto& w : words)
        if (!w.empty()) ++freq[w];
    logger->info("boost: {} words, {} unique", words.size(), freq.size());

    // --- abseil ---
    std::vector<std::string> parts{"abseil", "strings", "benchmark"};
    std::string joined = absl::StrJoin(parts, "-");
    logger->info("absl: {}", absl::StrCat("[", joined, "]"));

    // --- range-v3 ---
    auto squares_of_evens =
        ranges::views::iota(1, 101)
        | ranges::views::filter([](int n) { return n % 2 == 0; })
        | ranges::views::transform([](int n) { return n * n; })
        | ranges::to<std::vector>();
    logger->info("range-v3: {} even squares, last = {}",
                 squares_of_evens.size(), squares_of_evens.back());

    logger->info("benchmark_app finished successfully");
    return 0;
}
