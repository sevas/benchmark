#include "module_23.h"
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

int module_23_compute(int n) {
    auto joined = absl::StrJoin(std::vector<int>{n, n+1, n+2, n+3}, ", ", absl::AlphaNumFormatter()); return static_cast<int>(joined.size()) + n;
}
