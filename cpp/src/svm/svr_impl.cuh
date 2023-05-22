/*
 * Copyright (c) 2019-2023, NVIDIA CORPORATION.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#pragma once

/** @file svr_impl.cuh
 * @brief Implementation of the stateless C++ functions to fit an SVM regressor.
 */

#include <iostream>

#include "kernelcache.cuh"
#include "smosolver.cuh"
#include "svc_impl.cuh"
#include <cublas_v2.h>
#include <cuml/svm/svm_model.h>
#include <cuml/svm/svm_parameter.h>
#include <raft/core/handle.hpp>
#include <raft/distance/kernels.cuh>
#include <raft/linalg/unary_op.cuh>
#include <raft/matrix/matrix.cuh>
#include <thrust/copy.h>
#include <thrust/device_ptr.h>
#include <thrust/iterator/counting_iterator.h>

namespace ML {
namespace SVM {

template <typename math_t>
void svrFitX(const raft::handle_t& handle,
             const MLCommon::Matrix::Matrix<math_t>& matrix,
             math_t* y,
             const SvmParameter& param,
             raft::distance::kernels::KernelParams& kernel_params,
             SvmModel<math_t>& model,
             const math_t* sample_weight)
{
  int n_cols = matrix.get_n_cols();
  int n_rows = matrix.get_n_rows();

  ASSERT(n_cols > 0, "Parameter n_cols: number of columns cannot be less than one");
  ASSERT(n_rows > 0, "Parameter n_rows: number of rows cannot be less than one");

  // KernelCache could use multiple streams, not implemented currently
  // See Issue #948.
  // ML::detail::streamSyncer _(handle_impl.getImpl());
  const raft::handle_t& handle_impl = handle;

  cudaStream_t stream = handle_impl.get_stream();
  raft::distance::kernels::GramMatrixBase<math_t>* kernel =
    raft::distance::kernels::KernelFactory<math_t>::create(kernel_params);

  SmoSolver<math_t> smo(handle_impl, param, kernel_params.kernel, kernel);
  smo.Solve(matrix,
            n_rows,
            n_cols,
            y,
            sample_weight,
            &(model.dual_coefs),
            &(model.n_support),
            &(model.support_matrix),
            &(model.support_idx),
            &(model.b),
            param.max_iter);
  model.n_cols = n_cols;
  delete kernel;
}

template <typename math_t>
void svrFit(const raft::handle_t& handle,
            math_t* X,
            int n_rows,
            int n_cols,
            math_t* y,
            const SvmParameter& param,
            raft::distance::kernels::KernelParams& kernel_params,
            SvmModel<math_t>& model,
            const math_t* sample_weight)
{
  MLCommon::Matrix::DenseMatrix<math_t> dense_matrix(X, n_rows, n_cols);
  svrFitX(handle, dense_matrix, y, param, kernel_params, model, sample_weight);
}

template <typename math_t>
void svrFitSparse(const raft::handle_t& handle,
                  int* indptr,
                  int* indices,
                  math_t* data,
                  int n_rows,
                  int n_cols,
                  int nnz,
                  math_t* y,
                  const SvmParameter& param,
                  raft::distance::kernels::KernelParams& kernel_params,
                  SvmModel<math_t>& model,
                  const math_t* sample_weight)
{
  MLCommon::Matrix::CsrMatrix<math_t> csr_matrix(indptr, indices, data, nnz, n_rows, n_cols);
  svrFitX(handle, csr_matrix, y, param, kernel_params, model, sample_weight);
}

};  // end namespace SVM
};  // end namespace ML
