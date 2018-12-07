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

defmodule OMG.Watcher.ExitProcessor.CoreTest do
  @moduledoc """
  Test of the logic of exit processor - not losing exits from persistence, emitting events, talking to API.State.Core
  """
  use ExUnitFixtures
  use ExUnit.Case, async: true
  use OMG.API.Fixtures

  alias OMG.API.Crypto
  alias OMG.API.State
  alias OMG.API.State.Transaction
  alias OMG.API.Utxo
  alias OMG.Watcher.Eventer
  alias OMG.Watcher.Eventer.Event
  alias OMG.Watcher.ExitProcessor.Core

  require Utxo

  @moduletag :wrong

  @eth Crypto.zero_address()
  @not_eth <<1::size(160)>>

  @utxo_pos1 Utxo.position(1, 0, 0)
  @utxo_pos2 Utxo.Position.decode(10_000_000_001)


  deffixture processor_empty() do
    {:ok, empty} = Core.init([], [])
    empty
  end

  # exit_events is whatever `OMG.Eth` would feed into the `OMG.Watcher.ExitProcessor`, via `OMG.API.EthereumEventListener`
  deffixture exit_events(alice) do
    [
      %{amount: 10, currency: @eth, owner: alice.addr, utxo_pos: Utxo.Position.encode(@utxo_pos1), eth_height: 2},
      %{amount: 9, currency: @not_eth, owner: alice.addr, utxo_pos: Utxo.Position.encode(@utxo_pos2), eth_height: 4}
    ]
  end

  deffixture ife_events(alice) do
    signed =
      [@utxo_pos1, @utxo_pos2]
      |> Enum.map(&(Tuple.delete_at(&1, 0)))
      |> Transaction.new([{alice.addr, @eth, 10}, {alice.addr, @not_eth, 9}])
      |> Transaction.sign([alice.priv, alice.priv])
    [%{tx: signed}]
  end

  # extracts the mocked responses of the `Eth.RootChain.get_exit` for the exit events
  # all exits active (owner non-zero). This is the auxiliary, second argument that's fed into `new_exits`
  deffixture contract_statuses(exit_events) do
    exit_events
    |> Enum.map(fn %{amount: amount, currency: currency, owner: owner} -> {owner, currency, amount} end)
  end

  deffixture processor_filled(processor_empty, exit_events, contract_statuses) do
    {state, _} = Core.new_exits(processor_empty, exit_events, contract_statuses)
    state
  end

  @tag fixtures: [:processor_empty, :alice, :ife_events]
  test "active piggybacks from inputs are monitored", %{
    processor_empty: empty,
    ife_events: ife_events,
  } do
    Core.new_in_flight_exits(empty, [{timestamp: 1001}], ife_events)
  end

  @tag fixtures: [:processor_empty, :alice, :exit_events, :contract_statuses]
  test "persist started exits and loads persisted on init", %{
    processor_empty: empty,
    exit_events: exit_events,
    contract_statuses: contract_statuses
  } do
    keys = [@utxo_pos1, @utxo_pos2]
    values = Enum.map(exit_events, &(Map.put(&1, :is_active, true) |> Map.delete(:utxo_pos)))
    updates = Enum.zip([[:put, :put], [:exit_info, :exit_info], Enum.zip(keys, values)])
    update1 = Enum.slice(updates, 0, 1)
    update2 = Enum.slice(updates, 1, 1)

    assert {state2, ^update1} = Core.new_exits(empty, Enum.slice(exit_events, 0, 1), Enum.slice(contract_statuses, 0, 1))
    assert {final_state, ^updates} = Core.new_exits(empty, exit_events, contract_statuses)

    assert {^final_state, ^update2} =
             Core.new_exits(state2, Enum.slice(exit_events, 1, 1), Enum.slice(contract_statuses, 1, 1))

    {:ok, ^final_state} = Core.init(Enum.zip(keys, values))
  end

  @tag fixtures: [:processor_empty, :alice, :exit_events]
  test "new_exits sanity checks", %{processor_empty: processor, alice: %{addr: alice}, exit_events: [one_exit | _]} do
    {:error, :unexpected_events} =
      processor
      |> Core.new_exits([one_exit], [])

    {:error, :unexpected_events} =
      processor
      |> Core.new_exits([], [{alice, @eth, 10}])
  end

  @tag fixtures: [:processor_empty, :processor_filled]
  test "can process empty new exits or empty finalizations", %{processor_empty: empty, processor_filled: filled} do
    assert {^empty, []} = Core.new_exits(empty, [], [])
    assert {^filled, []} = Core.new_exits(filled, [], [])
    assert {^filled, []} = Core.finalize_exits(filled, {[], []})
  end

  @tag fixtures: [:processor_empty, :alice, :state_empty, :exit_events]
  test "handles invalid exit finalization - doesn't forget and activates", %{
    processor_empty: processor,
    alice: %{addr: alice},
    state_empty: state,
    exit_events: exit_events
  } do
    {processor, _} =
      processor
      |> Core.new_exits(
        exit_events,
        [{alice, @eth, 10}, {Crypto.zero_address(), @not_eth, 9}]
      )

    # exits invalidly finalize and continue/start emitting exit_events and complain
    {:ok, {_, _, two_spend}, state_after_spend} =
      State.Core.exit_utxos(
        [
          %{utxo_pos: Utxo.Position.encode(@utxo_pos1)},
          %{utxo_pos: Utxo.Position.encode(@utxo_pos2)}
        ],
        state
      )

    # finalizing here - note that without `finalize_exits`, we would just get a single invalid exit event
    # with - we get 3, because we include the invalidly finalized on which will hurt forever
    assert {processor,
            [
              {:put, :exit_info, {@utxo_pos1, %{is_active: true}}},
              {:put, :exit_info, {@utxo_pos2, %{is_active: true}}}
            ]} = Core.finalize_exits(processor, two_spend)

    assert {[_event1, _event2, _event3] = event_triggers, {:needs_stopping, :unchallenged_exit}} =
             processor
             |> Core.get_exiting_utxo_positions()
             |> Enum.map(&State.Core.utxo_exists?(&1, state_after_spend))
             |> Core.invalid_exits(processor, 12)

    # assert Eventer likes these triggers
    assert [_, _, _] = Eventer.Core.pair_events_with_topics(event_triggers)
  end

  @tag fixtures: [:processor_empty, :state_alice_deposit, :exit_events, :contract_statuses]
  test "can work with State to determine valid exits and finalize them", %{
    processor_empty: processor,
    state_alice_deposit: state,
    exit_events: [one_exit | _],
    contract_statuses: [one_status | _]
  } do
    {processor, _} =
      processor
      |> Core.new_exits([one_exit], [one_status])

    assert {[], :chain_ok} =
             processor
             |> Core.get_exiting_utxo_positions()
             |> Enum.map(&State.Core.utxo_exists?(&1, state))
             |> Core.invalid_exits(processor, 5)

    # go into the future - old exits work the same
    assert {[], :chain_ok} =
             processor
             |> Core.get_exiting_utxo_positions()
             |> Enum.map(&State.Core.utxo_exists?(&1, state))
             |> Core.invalid_exits(processor, 105)

    # exit validly finalizes and continues to not emit any exit_events
    {:ok, {_, _, spends}, _} = State.Core.exit_utxos([%{utxo_pos: Utxo.Position.encode(@utxo_pos1)}], state)
    assert {processor, [{:delete, :exit_info, @utxo_pos1}]} = Core.finalize_exits(processor, spends)
    assert [] = Core.get_exiting_utxo_positions(processor)
  end

  @tag fixtures: [:processor_empty, :state_empty, :exit_events, :contract_statuses]
  test "can work with State to determine and notify invalid exits", %{
    processor_empty: processor,
    state_empty: state,
    exit_events: [one_exit | _],
    contract_statuses: [one_status | _]
  } do
    exiting_position = Utxo.Position.encode(@utxo_pos1)

    {processor, _} =
      processor
      |> Core.new_exits([one_exit], [one_status])

    assert {[%Event.InvalidExit{utxo_pos: ^exiting_position}] = event_triggers, :chain_ok} =
             processor
             |> Core.get_exiting_utxo_positions()
             |> Enum.map(&State.Core.utxo_exists?(&1, state))
             |> Core.invalid_exits(processor, 5)

    # assert Eventer likes these triggers
    assert [_] = Eventer.Core.pair_events_with_topics(event_triggers)
  end

  @tag fixtures: [:processor_empty, :exit_events, :contract_statuses]
  test "can challenge exits, which are then forgotten completely", %{
    processor_empty: processor,
    exit_events: exit_events,
    contract_statuses: contract_statuses
  } do
    {processor, _} =
      processor
      |> Core.new_exits(exit_events, contract_statuses)

    # sanity
    assert [_, _] = processor |> Core.get_exiting_utxo_positions()

    assert {processor, [{:delete, :exit_info, @utxo_pos1}, {:delete, :exit_info, @utxo_pos2}]} =
             processor
             |> Core.challenge_exits([
               %{utxo_pos: Utxo.Position.encode(@utxo_pos1)},
               %{utxo_pos: Utxo.Position.encode(@utxo_pos2)}
             ])

    assert [] = processor |> Core.get_exiting_utxo_positions()
  end

  @tag fixtures: [:processor_empty, :state_empty, :exit_events, :contract_statuses]
  test "can work with State to determine invalid exits entered too late", %{
    processor_empty: processor,
    state_empty: state,
    exit_events: [one_exit | _],
    contract_statuses: [one_status | _]
  } do
    exiting_position = Utxo.Position.encode(@utxo_pos1)

    {processor, _} =
      processor
      |> Core.new_exits([one_exit], [one_status])

    assert {[%Event.UnchallengedExit{utxo_pos: ^exiting_position}, %Event.InvalidExit{utxo_pos: ^exiting_position}] =
              event_triggers,
            {:needs_stopping, :unchallenged_exit}} =
             processor
             |> Core.get_exiting_utxo_positions()
             |> Enum.map(&State.Core.utxo_exists?(&1, state))
             |> Core.invalid_exits(processor, 13)

    # assert Eventer likes these triggers
    assert [_, _] = Eventer.Core.pair_events_with_topics(event_triggers)
  end

  @tag fixtures: [:processor_empty, :state_empty, :exit_events, :contract_statuses]
  test "invalid exits that have been witnessed already inactive don't excite exit_events", %{
    processor_empty: processor,
    state_empty: state,
    exit_events: [one_exit | _]
  } do
    {processor, _} =
      processor
      |> Core.new_exits([one_exit], [{Crypto.zero_address(), @eth, 10}])

    assert {[], :chain_ok} =
             processor
             |> Core.get_exiting_utxo_positions()
             |> Enum.map(&State.Core.utxo_exists?(&1, state))
             |> Core.invalid_exits(processor, 13)
  end

  @tag fixtures: [:processor_empty]
  test "empty processor returns no exiting utxo positions", %{processor_empty: empty} do
    assert [] = Core.get_exiting_utxo_positions(empty)
  end
end
