defmodule QuillEx.Metrics.Instrumenter do
    require Logger
    # alias QuillEx.Metrics.Stash

    @stash :stash

    @render_start [:render, :start]
    @render_finish [:render, :finish]

    def setup do

        # {:ok, _pid} = Agent.start_link(fn -> %{start: nil} end, name: @datastore)
        {:ok, _pid} = Agent.start_link(fn -> %{start: :init} end, name: @stash)

        events = [
            @render_start,
            @render_finish
        ]

        :telemetry.attach_many("quillex-perf-meter", events, &__MODULE__.handle_event/4, nil)
    end
  
    def handle_event(e = @render_start, %{timestamp: start_t}, metadata, _config) do
        # QuillEx.Metrics.Stash.start(start_t)
        Agent.update(@stash, fn
            %{start: nil} ->
                %{start: start_t}
            _otherwise ->
                Logger.warn "recv'd start event before corresponding finish"
                %{start: nil}
          end)
    end

    def handle_event(e = @render_finish, %{timestamp: end_t}, metadata, _config) do
        # QuillEx.Metrics.Stash.stop(end_t)
        Agent.update(@stash, fn
            %{start: :init} ->
              Logger.warn "ignoring first finish draw..."
              %{start: nil}
            %{start: start_t} when not is_nil(start_t) ->
              ms = System.convert_time_unit(end_t - start_t, :native, :millisecond)
              Logger.info "Loop time: #{inspect ms}ms"
              %{start: nil}
          _otherwise ->
              Logger.warn "recv'd finish event without a start event"
              %{start: nil}
          end)
    end

end