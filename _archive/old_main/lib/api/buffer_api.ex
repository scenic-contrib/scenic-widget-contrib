defmodule QuillEx.API.Buffer do
  @doc """
  Open a blank, unsaved buffer.
  """
  alias QuillEx.Reducers.BufferReducer

  def new do
    QuillEx.action({BufferReducer, {:open_buffer, %{data: "", mode: :edit}}})
  end

  def new(raw_text) when is_bitstring(raw_text) do
    QuillEx.action({BufferReducer, {:open_buffer, %{data: raw_text, mode: :edit}}})
  end

  @doc """
  Return the active Buffer.
  """
  def active_buf do
    QuillEx.Fluxus.RadixStore.get().editor.active_buf
  end

  @doc """
  Set which buffer is the active buffer.
  """
  def activate(buffer_ref) do
    QuillEx.action({BufferReducer, {:activate, buffer_ref}})
  end

  @doc """
  Set which buffer is the active buffer.

  This function does the same thing as `activate/1`, it's just another
  entry point via the API, included for better DX (dev-experience).
  """
  def switch({:buffer, _name} = buffer_ref) do
    QuillEx.action({BufferReducer, {:activate, buffer_ref}})
  end

  @doc """
  Scroll the buffer around.
  """
  def scroll({_x_scroll, _y_scroll} = scroll_delta) do
    QuillEx.action({BufferReducer, {:scroll, :active_buf, {:delta, scroll_delta}}})
  end

  @doc """
  Scroll the buffer around.
  """
  def move_cursor({_column_delta, _line_delta} = cursor_move_delta) do
    QuillEx.action({BufferReducer, {:move_cursor, {:delta, cursor_move_delta}}})
  end

  @doc """
  List all the open buffers.
  """
  def list do
    QuillEx.Fluxus.RadixStore.get().editor.buffers
  end

  def open do
    open("./README.md")
  end

  def open(filepath) do
    QuillEx.action({BufferReducer, {:open_buffer, %{filepath: filepath, mode: :edit}}})
  end

  def find(search_term) do
    raise "cant find yet"
  end

  @doc """
  Return the contents of a buffer.
  """
  def read(buf) do
    [buf] = list() |> Enum.filter(&(&1.id == buf))
    buf.data
  end

  def modify(buf, mod) do
    QuillEx.action({BufferReducer, {:modify_buf, buf, mod}})
  end

  def save(buf) do
    QuillEx.action({BufferReducer, {:save_buffer, buf}})
  end

  def close do
    active_buf() |> close()
  end

  def close(buf) do
    QuillEx.action({BufferReducer, {:close_buffer, buf}})
  end
end

# defmodule Flamelex.Buffer.Text do
#   @moduledoc """
#   A buffer to hold & manipulate text.
#   """
#   use Flamelex.BufferBehaviour
#   alias Flamelex.Buffer.Utils.TextBufferUtils
#   alias Flamelex.Buffer.Utils.TextBuffer.ModifyHelper
#   alias Flamelex.Buffer.Utils.CursorMovementUtils, as: MoveCursor
#   # require Logger

#   def boot_sequence(%{source: :none, data: file_contents} = params) do
#     init_state =
#       params |> Map.merge(%{
#         unsaved_changes?: false,  # a flag to say if we have unsaved changes
#         # time_opened #TODO
#         cursors: [%{line: 1, col: 1}],
#         lines: file_contents |> TextBufferUtils.parse_raw_text_into_lines()
#       })

#     {:ok, init_state}
#   end

#   @impl Flamelex.BufferBehaviour
#   def boot_sequence(%{source: {:file, filepath}} = params) do
#     # Logger.info "#{__MODULE__} booting up... #{inspect params, pretty: true}"

#     {:ok, file_contents} = File.read(filepath)

#     init_state =
#       params |> Map.merge(%{
#         data: file_contents,    # the raw data
#         unsaved_changes?: false,  # a flag to say if we have unsaved changes
#         # time_opened #TODO
#         cursors: [%{line: 1, col: 1}],
#         lines: file_contents |> TextBufferUtils.parse_raw_text_into_lines()
#       })

#     {:ok, init_state}
#   end

#   def find_supervisor_pid(%{rego_tag: rego_tag = {:buffer, _details}}) do
#     ProcessRegistry.find!({:buffer, :task_supervisor, rego_tag})
#   end

#   # #TODO right now, this only works for one cursor, i.e. cursor-1
#   # def handle_call({:get_cursor_coords, 1}, _from, %{cursors: [c]} = state) do
#   #   {:reply, c, state}
#   # end

#   def handle_call(:get_num_lines, _from, state) do
#     {:reply, Enum.count(state.lines), state}
#   end

#   @impl GenServer
#   def handle_call(:save, _from, %{source: {:file, _filepath}} = state) do
#     {:ok, new_state} = TextBufferUtils.save(state)
#     {:reply, :ok, new_state}
#   end

#   def handle_cast(:close, %{unsaved_changes?: true} = state) do
#     #TODO need to raise a bigger alarm here
#     # Logger.warn "unable to save buffer: #{inspect state.rego_tag}, as it contains unsaved changes."
#     {:noreply, state}
#   end

#   def handle_cast(:close, %{unsaved_changes?: false} = state) do
#     Logger.debug "#{__MODULE__} received msg: :close - process will stop normally."
#     # {:buffer, source} = state.rego_tag
#     # Logger.warn "Closing a buffer... #{inspect source}"
#     # ModifyHelper.cast_gui_component(source, :close)
#     IO.puts "#TODO need to actually close the buffer - close the FIle?"

#     # ProcessRegistry.find!({:gui_component, state.rego_tag}) #TODO this should be a GUI.Component.TextBox, not, :gui_component !!
#     # |> GenServer.cast(:close)

#     GenServer.cast(Flamelex.GUI.Controller, {:close, state.rego_tag})

#     {:stop, :normal, state}
#   end

#   def handle_cast({:move_cursor, instructions}, state) do
#     start_sub_task(state, MoveCursor,
#                           :move_cursor_and_update_gui,
#                           instructions)
#     {:noreply, state}
#   end

#   # def handle_cast({:modify, details}, state) do
#   def handle_call({:modify, details}, _from, state) do
#     ModifyHelper.start_modification_task(state, details)
#     # :timer.sleep(100)
#     {:reply, :ok, state}
#   end

#   # when a Task completes, if successful, it will most likely callback -
#   # so we update the state of the Buffer, & trigger a GUI update
#   #TODO maybe this is a little ambitious... we can just do what MoveCursor does, and have the task directly call the GUI to update it specifically
#   # def handle_cast({:state_update, new_state}, %{rego_tag: buffer_rego_tag = {:buffer, _details}}) do
#   #   PubSub.broadcast(
#   #     topic: :gui_update_bus,
#   #       msg: {buffer_rego_tag, {:new_state, new_state}})
#   #   {:noreply, new_state}
#   # end

#   def handle_cast({:state_update, new_state}, _old_state) do
#     Logger.debug "#{__MODULE__} updating state - #{inspect new_state.data}"
#     #TODO this is where the GUI should be triggered, not the othe way around
#     #TODO need to update the GUI here?
#     {:noreply, new_state}
#   end

#   # spin up a new process to do the handling...
#   defp start_sub_task(state, module, function, args) do
#   Task.Supervisor.start_child(
#       find_supervisor_pid(state), # start the task under the Task.Supervisor specific to this Buffer
#           module,
#           function,
#           [state, args])
#   end
# end
