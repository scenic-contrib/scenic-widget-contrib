defmodule QuillEx.Reducers.BufferReducer.Utils do

   # finds the active_buf by default
   def filter_active_buf(%{editor: %{buffers: buf_list, active_buf: active_buf}}) when not is_nil(active_buf) do
      filter_buf(buf_list, active_buf)
   end

   def filter_buf(%{editor: %{buffers: buf_list}}, buf_id) do
      filter_buf(buf_list, buf_id)
   end

   def filter_buf(buf_list, buf_id) when is_list(buf_list) and length(buf_list) >= 1 do
      [buffer = %{id: ^buf_id}] = buf_list |> Enum.filter(&(&1.id == buf_id))
      buffer
   end

   def update_active_buf(radix_state, changes) do
      active_buf = filter_active_buf(radix_state)
      update_buf(radix_state, active_buf, changes)
   end

   def update_buf(radix_state, %{id: old_buf_id}, changes) do
      update_buf(radix_state, old_buf_id, changes)
   end

   def update_buf(%{editor: %{buffers: buf_list}} = radix_state, {:buffer, _id} = old_buf_id, changes) do
      radix_state
      |> put_in([:editor, :buffers], buf_list |> Enum.map(fn
         %{id: ^old_buf_id} = old_buf ->
            QuillEx.Structs.Buffer.update(old_buf, changes)
         any_other_buffer ->
            any_other_buffer
      end))
   end

   def calc_capped_scroll(radix_state, {:delta, {delta_x, delta_y}}) do
      # Thanks @vacarsu for this snippet <3 <3 <3
      # The most complex idea here is that to scroll to the right, we
      # need to translate the text to the _left_, which means applying
      # a negative translation, and visa-versa for vertical scroll
  
      scroll_acc = {scroll_acc_w, scroll_acc_y} = filter_active_buf(radix_state).scroll_acc
      # invrt_scroll = radix_state.gui_config.editor.invert_scroll
      # scroll_acc_w = if invrt_scroll.horizontal?, do: (-1*scroll_acc_w), else: scroll_acc_w
      # scroll_acc_y = if invrt_scroll.vertical?, do: (-1*scroll_acc_y), else: scroll_acc_y
      scroll_speed = radix_state.editor.config.scroll.speed
  
      %{
        frame: %{size: {frame_w, frame_h}},
        inner: %{width: inner_w, height: inner_h}
          } = radix_state.editor.scroll_state
  
      # new_x_scroll_acc_value =
      #   if inner_w < frame_w do
      #     0
      #   else
      #     delta_x
      #   end
  
      # {new_x_scroll_acc_value, 0} #TODO handle vertical scroll
  
      # #TODO make this configurable
      # invert_horizontal_scroll? = true
      # x_scroll_factor = if invert_horizontal_scroll?, do: -1*scroll_speed.horizontal, else: scroll_speed.horizontal
  
  
      horizontal_delta =
        scroll_speed.horizontal*delta_x
      vertical_delta =
        scroll_speed.vertical*delta_y
      # horizontal_delta =
      #   if invrt_scroll.horizontal?, do: (-1*scaled_delta_x), else: scaled_delta_x
      # IO.inspect horizontal_delta, label: "HHHXXX"
  
      scrolling_right? =
        horizontal_delta > 0
      scrolling_left? =
        vertical_delta < 0
      inner_contents_smaller_than_outer_frame_horizontally? =
        inner_w < frame_w
      inner_contents_smaller_than_outer_frame_vertically? =
        inner_h < frame_h
  
      # scroll_has_hit_max? =
      #   (frame_w + scroll_acc_w) >= inner_w #TODO use margin, get it from radix_state
      # # we_are_at_max_scroll? =
      # #   (frame_w + scroll_acc_w) >= inner_w
      # we_are_at_min_scroll? =
      #   scroll_acc_w >= 0
        
      final_x_delta =
        if inner_contents_smaller_than_outer_frame_horizontally? do
          0 # no need to scroll at all
        else
          # NOTE: To scroll to the right, we need to translate to the left, i.e. apply
          # a negative translation, but scroll signals to the right come in as positive
          # values from our input device, so we flip it here to achieve the desired effect
          -1*horizontal_delta
        end
  
      final_y_delta =
        if inner_contents_smaller_than_outer_frame_vertically? do
          0 # no need to scroll at all
        else
          # NOTE: To scroll down, we need to translate up, i.e. apply a negative
          # translation. Since scroll signals to scroll up come in as negative
          # values from our input device, we don't need to flip them here
          vertical_delta
        end
  
      #TODO 2 things
      # - seems like when we make a lot of new lines, we break something...
      # - we need to take into effect the scroll bars reducing the frame size. We should probably put a border around the scroll bars.... well, they'll be hidden if there's nothing to see I guess
  
      res = {res_x, res_y} = Scenic.Math.Vector2.add(scroll_acc, {final_x_delta, final_y_delta})
  
      res_x = max(res_x, (-1*(inner_w-frame_w+10))) #TODO why does 10 work so good here>?>??>
      res_x = min(res_x, 0)
  
      res_y = max(res_y, (-1*(inner_h-frame_h+10))) #TODO why does 10 work so good here>?>??>
      res_y = min(res_y, 0)
  
      {res_x, res_y}
  
      # if height > frame.dimensions.height do
      #   coord
      #   |> calc_floor({0, -height + frame.dimensions.height / 2})
      #   |> calc_ceil({0, 0})
      # else
      #   coord
      #   |> calc_floor(@min_position_cap)
      #   |> calc_ceil(@min_position_cap)
      # end
   end

   # these functions are used to cap scrolling
   def apply_floor({x, y}, {min_x, min_y}) do
      {max(x, min_x), max(y, min_y)}
   end

   def apply_ceil({x, y}, {max_x, max_y}) do
      {min(x, max_x), min(y, max_y)}
   end
  
end