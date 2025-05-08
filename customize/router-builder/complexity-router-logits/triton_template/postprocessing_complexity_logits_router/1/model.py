# SPDX-FileCopyrightText: Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import numpy as np
import triton_python_backend_utils as pb_utils
from logits_processor import LogitsProcessor
from transformers import AutoConfig

class TritonPythonModel:
    def initialize(self, args):
        self.logger = pb_utils.Logger
        self.config = AutoConfig.from_pretrained("nvidia/prompt-task-and-complexity-classifier")
        
        # Load the necessary configurations
        self.target_sizes = self.config.target_sizes
        self.task_type_map = self.config.task_type_map
        self.weights_map = self.config.weights_map
        self.divisor_map = self.config.divisor_map
        
        # Initialize the LogitsProcessor
        self.processor = LogitsProcessor(
            task_type_map=self.task_type_map,
            weights_map=self.weights_map,
            divisor_map=self.divisor_map)
        
        # complexity metrics from config
        self.complexity_metrics = []
        for metric in self.weights_map.keys():
            if metric != "task_type" and metric in self.divisor_map:
                self.complexity_metrics.append(metric)
        
        self.logger.log_info(f"Using complexity metrics: {self.complexity_metrics}")
        self.logger.log_info("Initialization complete")

    def execute(self, requests):
        self.logger.log_info(f"Executing {len(requests)} requests")
        responses = []
        
        for request in requests:
            logits = pb_utils.get_input_tensor_by_name(request, "logits").as_numpy()
            self.logger.log_info(f"Logits Shape: {logits.shape}")

            # Process logits into separate outputs for each target
            processed_logits = self.process_results(logits, self.target_sizes.values())
            result = self.processor.process_logits(processed_logits)

            # Build output vector: [complexity_score, creativity, reasoning, contextual_knowledge, number_of_few_shots, domain_knowledge, constraint_ct]
            # All are lists of length batch_size, so we need to stack them per sample
            batch_size = len(result["prompt_complexity_score"])
            output_vectors = []
            for i in range(batch_size):
                vector = [
                    result["prompt_complexity_score"][i],
                    result["creativity_scope"][i],
                    result["reasoning"][i],
                    result["contextual_knowledge"][i],
                    result["number_of_few_shots"][i],
                    result["domain_knowledge"][i],
                    result["constraint_ct"][i],
                ]
                output_vectors.append(vector)
            output_array = np.array(output_vectors, dtype=np.float32)
            self.logger.log_info(f"Output vector shape: {output_array.shape}")

            output_tensor = pb_utils.Tensor("OUTPUT", output_array)
            inference_response = pb_utils.InferenceResponse(output_tensors=[output_tensor])
            responses.append(inference_response)
        
        return responses

    def process_results(self, output_tensor, target_sizes):
        results = []
        start_idx = 0
        for size in target_sizes:
            end_idx = start_idx + size
            result = output_tensor[:, start_idx:end_idx]
            results.append(result)
            start_idx = end_idx
        return results

    def finalize(self):
        self.logger.log_info("Finalizing TritonPythonModel")
