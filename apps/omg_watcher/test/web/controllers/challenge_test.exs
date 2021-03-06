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

defmodule OMG.Watcher.Web.Controller.ChallengeTest do
  use ExUnitFixtures
  use ExUnit.Case, async: false
  use OMG.API.Fixtures

  alias OMG.API
  alias OMG.API.Crypto
  alias OMG.API.Utxo
  alias OMG.Watcher.DB
  alias OMG.Watcher.TestHelper

  require Utxo

  @eth Crypto.zero_address()

  @tag fixtures: [:phoenix_ecto_sandbox, :alice]
  test "challenge data is properly formatted", %{alice: alice} do
    DB.EthEvent.insert_deposits([%{owner: alice.addr, currency: @eth, amount: 100, blknum: 1}])

    DB.Transaction.update_with(%{
      transactions: [
        API.TestHelper.create_recovered([{1, 0, 0, alice}], @eth, [{alice, 100}])
      ],
      blknum: 1000,
      blkhash: <<?#::256>>,
      timestamp: :os.system_time(:second),
      eth_height: 1
    })

    utxo_pos = Utxo.position(1, 0, 0) |> Utxo.Position.encode()

    %{
      "inputIndex" => _input_index,
      "outputId" => _output_id,
      "sig" => _sig,
      "txbytes" => _txbytes
    } = TestHelper.success?("utxo.get_challenge_data", %{"utxo_pos" => utxo_pos})
  end

  @tag fixtures: [:phoenix_ecto_sandbox]
  test "challenging non-existent utxo returns error" do
    utxo_pos = Utxo.position(1, 1, 0) |> Utxo.Position.encode()

    %{
      "code" => "challenge:invalid",
      "description" => "The challenge of particular exit is invalid because provided utxo is not spent"
    } = TestHelper.no_success?("utxo.get_challenge_data", %{"utxo_pos" => utxo_pos})
  end
end
