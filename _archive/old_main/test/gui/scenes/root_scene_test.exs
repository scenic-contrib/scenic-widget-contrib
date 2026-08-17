defmodule QuillEx.Scene.RootSceneTest do
    use ExUnit.Case
    alias QuillEx.Scene.RootScene

    test "basic render" do
        test_viewport = %Scenic.ViewPort{size: {_vp_width = 200, _vp_height = 200}}

        test_radix_state = %{
            menu_map: [], 
            editor: %{buffers: []},
            gui_config: %{
                fonts: %{
                    menu_bar: %{
                        name: :roboto,
                        size: 24
                    }
                }
            }
        }

        %Scenic.Graph{} = RootScene.render(test_viewport, test_radix_state)
    end
end