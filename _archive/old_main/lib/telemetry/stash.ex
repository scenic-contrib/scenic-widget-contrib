defmodule QuillEx.Metrics.Stash do
    use Agent
    require Logger
  
    def start_link(args) do
      Agent.start_link(fn -> %{start: :init} end, name: __MODULE__)
    end
  
    def start(start_t) do
      Agent.update(__MODULE__, fn
        %{start: nil} ->
            %{start: start_t}
        _otherwise ->
            Logger.warn "recv'd start event before corresponding finish"
            %{start: nil}
      end)
    end
      
    def stop(end_t) do
      Agent.update(__MODULE__, fn
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