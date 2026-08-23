defmodule QuillEx.Reducers.BufferReducerTest do
   use ExUnit.Case

   @testmodule QuillEx.Reducers.BufferReducer

   describe "open a new Buffer with none currently open" do
      setup [
         :construct_radix_state,
         :open_new_buffer_with_none_currently_open
      ]

      test "active_buffer is not nil", %{result: result} do
         assert not is_nil(result.editor.active_buf)
      end

      test "sets the active app to :editor", %{result: result} do
         assert result.root.active_app == :editor
      end

   end


   def construct_radix_state(context) do
      test_viewport = %Scenic.ViewPort{size: {_vp_width = 200, _vp_height = 200}}
      rdx = QuillEx.Fluxus.Structs.RadixState.new() |> put_in([:gui, :viewport], test_viewport)
      
      context |> Map.merge(%{radix_state: rdx})
   end

   def open_new_buffer_with_none_currently_open(%{radix_state: rdx} = context) do
      {:ok, result} = @testmodule.process(rdx, {:open_buffer, %{data: ""}})
      context |> Map.merge(%{result: result})
   end

end