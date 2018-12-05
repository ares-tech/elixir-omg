# Copyright 2018 OmiseGO Pte Ltd
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule OMG.Watcher.ExitProcessor.CompetitorInfo do
  @moduledoc """
  Represents the bulk of information about a competitor to an IFE.

  Internal stuff of `OMG.Watcher.ExitProcessor`
  """

  alias OMG.API.Crypto
  alias OMG.API.Utxo

  # mapped by :in_flight_exit_id
  defstruct [
    :competing_in_flight_tx,
    :tx_bytes,
    :inclusion_proof,
    :competing_input_index,
    :competing_input_signature
  ]

  # TODO
  #  @type t :: %__MODULE__{
  #               competing_in_flight_tx: ,
  #               :tx_bytes,
  #               :inclusion_proof,
  #               :competing_input_index,
  #               :competing_input_signature
  #             }
end
