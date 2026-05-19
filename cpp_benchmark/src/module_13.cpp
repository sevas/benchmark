#include "module_13.h"
#include <boost/algorithm/string.hpp>
#include <boost/container/flat_map.hpp>
#include <boost/container/flat_set.hpp>
#include <boost/lexical_cast.hpp>
#include <boost/algorithm/string/split.hpp>
#include <boost/algorithm/string/classification.hpp>
#include <Eigen/Dense>
#include <Eigen/Sparse>
#include <Eigen/Eigenvalues>
#include <fmt/format.h>
#include <fmt/ranges.h>
#include <fmt/chrono.h>
#include <spdlog/spdlog.h>
#include <spdlog/sinks/stdout_color_sinks.h>
#include <nlohmann/json.hpp>
#include <absl/strings/str_cat.h>
#include <absl/strings/str_join.h>
#include <absl/strings/str_split.h>
#include <range/v3/view/filter.hpp>
#include <range/v3/view/transform.hpp>
#include <range/v3/view/iota.hpp>
#include <range/v3/view/take.hpp>
#include <range/v3/numeric/accumulate.hpp>
#include <range/v3/to_container.hpp>
#include <vector>
#include <string>
#include <numeric>

int module_13_compute(int n) {
    auto sq = ranges::views::iota(1, n%12+2) | ranges::views::transform([](int x){ return x*x*x; }) | ranges::to<std::vector<int>>(); return ranges::accumulate(sq, 0) % 1000;
}
