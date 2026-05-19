"""
Measures the cold-import cost of several heavy scientific Python libraries.

Outputs two lines that the PS1 runner parses:
    import_time_seconds=<float>
    modules_loaded=<int>

MPLBACKEND=Agg should be set by the caller to avoid GUI/font-cache noise.
"""

import sys
import time

t0 = time.perf_counter()

# NumPy — loads BLAS/LAPACK C extensions
import numpy as np
import numpy.linalg
import numpy.fft
import numpy.random

# SciPy — large C-extension tree
import scipy
import scipy.linalg
import scipy.stats
import scipy.optimize
import scipy.signal
import scipy.fft
import scipy.sparse
import scipy.interpolate

# Matplotlib — triggers font/style discovery
import matplotlib
import matplotlib.pyplot as plt
import matplotlib.cm
import matplotlib.colors
import matplotlib.patches
import matplotlib.path
import matplotlib.ticker
import matplotlib.animation

# Pandas — loads its own C extensions + datetime machinery
import pandas as pd
import pandas.core.frame
import pandas.io.formats.style

# PyTorch — largest single import; loads ATen, autograd, JIT
import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
import torch.utils.data
import torch.autograd
import torch.distributions

t1 = time.perf_counter()

elapsed      = t1 - t0
all_modules  = list(sys.modules.keys())
n_total      = len(all_modules)
top_packages = sorted(set(m.split(".")[0] for m in all_modules))
n_top        = len(top_packages)

print(f"import_time_seconds={elapsed:.6f}", flush=True)
print(f"modules_loaded={n_total}", flush=True)
print(f"top_level_packages={n_top}", flush=True)
# One line per top-level package so the PS1 can list them in the report
print(f"packages_list={','.join(top_packages)}", flush=True)
