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

defmodule OMG.Watcher.ExitProcessor.InFlightExitInfo do
  @moduledoc """
  Represents the bulk of information about a tracked in-flight exit.

  Internal stuff of `OMG.Watcher.ExitProcessor`
  """

  alias OMG.API.State.Transaction
  alias OMG.API.Utxo

  # mapped by :in_flight_exit_id
  defstruct [
    :tx,
    :tx_pos,
    :timestamp,
    # piggybacking
    exit_map: <<0::16>>,
    oldest_competitor: 0,
    is_canonical: true
  ]

  @type t :: %__MODULE__{
          tx: Transaction.Signed.t(),
          tx_pos: Utxo.Position.t(),
          timestamp: non_neg_integer(),
          exit_map: binary(),
          oldest_competitor: non_neg_integer(),
          is_canonical: boolean()
        }

  def get_exit_id_from_tx_hash(tx_hash) when is_binary(tx_hash) and byte_size(tx_hash) == 32 do
    # cut the oldest 8 bytes and shift left by one bit (least significant bit is set to 0)
    <<_::65, ife_id::bitstring-size(192)>> = <<tx_hash::bitstring, <<0::1>>::bitstring>>
    ife_id
  end

  def build_in_flight_transaction_info(tx_bytes, tx_signatures, timestamp) do
    with {:ok, raw_tx, []} <- Transaction.decode(tx_bytes) do
      signed_tx_map = %{
        raw_tx: raw_tx,
        sigs: tx_signatures
      }

      {
        Transaction.hash(raw_tx),
        %__MODULE__{
          tx: struct(Transaction.Signed, signed_tx_map),
          timestamp: timestamp
        }
      }
    end
  end

  def make_db_update({ife_hash, %__MODULE__{} = ife_info}) do
    {:put, :in_flight_exit_info, {ife_hash, ife_info}}
  end
end
