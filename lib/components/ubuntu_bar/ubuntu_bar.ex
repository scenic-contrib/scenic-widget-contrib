defmodule ScenicWidgets.UbuntuBar do
  @moduledoc """
  UbuntuBar - A vertical sidebar component with configurable icon buttons.
  
  Similar to Ubuntu's left sidebar or VS Code's activity bar, this component
  displays a vertical column of clickable icon buttons.
  
  ## Usage
  
      # Add to graph with default settings
      graph |> ScenicWidgets.UbuntuBar.add_to_graph(%{}, frame: frame)
      
      # Add to graph with custom buttons
      buttons = [
        %{id: :files, glyph: "📁", tooltip: "Files"},
        %{id: :search, glyph: "🔍", tooltip: "Search"},
        %{id: :git, glyph: "📝", tooltip: "Git"}
      ]
      
      data = %{
        buttons: buttons,
        button_size: 50,
        background_color: {45, 45, 45},
        active_button: :files
      }
      
      graph |> ScenicWidgets.UbuntuBar.add_to_graph(data, frame: frame)
  """
  
  use Scenic.Component
  require Logger
  import Scenic.Primitives

  @impl Scenic.Component
  def validate(data) when is_map(data) do
    # Convert to a normalized format with defaults
    normalized = %{
      buttons: Map.get(data, :buttons, default_buttons()),
      button_size: Map.get(data, :button_size, 50),
      background_color: Map.get(data, :background_color, {40, 40, 40}),
      button_color: Map.get(data, :button_color, {60, 60, 60}),
      button_hover_color: Map.get(data, :button_hover_color, {80, 80, 80}),
      button_active_color: Map.get(data, :button_active_color, {100, 150, 200}),
      text_color: Map.get(data, :text_color, {220, 220, 220}),
      active_button: Map.get(data, :active_button),
      font_size: Map.get(data, :font_size),
      layout: Map.get(data, :layout, :center), # :top, :center, :bottom
      button_spacing: Map.get(data, :button_spacing, 8),
      font_family: Map.get(data, :font_family, nil), # For cool fonts!
      padding: Map.get(data, :padding, %{top: 10, bottom: 10}),
      remove_top_margin: Map.get(data, :remove_top_margin, false) # For visual alignment when menubar is above
    }
    
    # Validate layout option
    if normalized.layout not in [:top, :center, :bottom] do
      {:error, "layout must be one of: :top, :center, :bottom"}
    else
      {:ok, normalized}
    end
  end
  
  def validate(data) do
    {:error, "UbuntuBar data must be a map, got: #{inspect(data)}"}
  end

  @impl Scenic.Component  
  def init(scene, data, opts) do
    # Extract frame from opts
    frame = case Keyword.get(opts, :frame) do
      %{size: %{width: _w, height: _h}} = f -> f
      _ -> 
        Logger.error("UbuntuBar requires a frame in opts")
        %{size: %{width: 60, height: 400}} # fallback
    end

    # Build state from validated data and defaults
    button_size = min(data.button_size, frame.size.width - 4)
    font_size = data.font_size || button_size * 0.6
    
    state = %{
      buttons: data.buttons,
      button_size: button_size,
      background_color: data.background_color,
      button_color: data.button_color,
      button_hover_color: data.button_hover_color,
      button_active_color: data.button_active_color,
      text_color: data.text_color,
      active_button: data.active_button,
      hovered_button: nil,
      font_size: font_size,
      layout: data.layout,
      button_spacing: data.button_spacing,
      font_family: data.font_family,
      padding: data.padding,
      remove_top_margin: data.remove_top_margin,
      frame: frame
    }

    # Build the graph
    graph = render_ubuntu_bar(Scenic.Graph.build(), state)
    
    scene = 
      scene
      |> assign(state: state)
      |> push_graph(graph)

    request_input(scene, [:cursor_button, :cursor_pos])
    
    {:ok, scene}
  end

  @impl Scenic.Component
  def handle_cast({:set_active_button, button_id}, scene) do
    new_state = %{scene.assigns.state | active_button: button_id}
    new_graph = render_ubuntu_bar(Scenic.Graph.build(), new_state)
    
    scene =
      scene
      |> assign(state: new_state)
      |> push_graph(new_graph)
    
    {:noreply, scene}
  end

  @impl Scenic.Component
  def handle_input(
        {:cursor_button, {:btn_left, 1, _empty_list?, _local_coords}},
        {:button_bg, button_id},
        scene
      ) do
    state = scene.assigns.state
    
    # Find the button that was clicked
    button = Enum.find(state.buttons, &(&1.id == button_id))
    
    if button do
      # Send event to parent - this is the proper Scenic way to communicate up the tree
      send_parent_event(scene, {:ubuntu_bar_button_clicked, button_id, button})
      
      # Update active button for visual feedback
      new_state = %{state | active_button: button_id}
      new_graph = render_ubuntu_bar(Scenic.Graph.build(), new_state)
      
      scene = 
        scene
        |> assign(state: new_state)
        |> push_graph(new_graph)
      
      {:noreply, scene}
    else
      Logger.warning("Unknown button clicked: #{inspect(button_id)}")
      {:noreply, scene}
    end
  end

  @impl Scenic.Component
  def handle_input({:cursor_pos, _coords}, {:button_bg, button_id}, scene) do
    state = scene.assigns.state
    
    # Update hovered button if it changed
    if state.hovered_button != button_id do
      new_state = %{state | hovered_button: button_id}
      new_graph = render_ubuntu_bar(Scenic.Graph.build(), new_state)
      
      scene = 
        scene
        |> assign(state: new_state)
        |> push_graph(new_graph)
      
      {:noreply, scene}
    else
      {:noreply, scene}
    end
  end

  @impl Scenic.Component
  def handle_input({:cursor_pos, _coords}, _context, scene) do
    state = scene.assigns.state
    
    # Clear hovered button when cursor leaves button area
    if state.hovered_button != nil do
      new_state = %{state | hovered_button: nil}
      new_graph = render_ubuntu_bar(Scenic.Graph.build(), new_state)
      
      scene = 
        scene
        |> assign(state: new_state)
        |> push_graph(new_graph)
      
      {:noreply, scene}
    else
      {:noreply, scene}
    end
  end

  @impl Scenic.Component
  def handle_input({:cursor_button, _details} = input, _context, scene) do
    # Logger.debug("#{__MODULE__} ignoring input: #{inspect(input)}")
    {:noreply, scene}
  end

  @impl Scenic.Component
  def handle_input(input, context, scene) do
    # Logger.debug("#{__MODULE__} unhandled input: #{inspect(input)} context: #{inspect(context)}")
    {:noreply, scene}
  end

  # Default set of buttons for demonstration/testing
  def default_buttons() do
    [
      %{id: :files, glyph: "F", tooltip: "Files"},
      %{id: :search, glyph: "S", tooltip: "Search"},
      %{id: :git, glyph: "G", tooltip: "Source Control"},
      %{id: :debug, glyph: "D", tooltip: "Debug"},
      %{id: :extensions, glyph: "E", tooltip: "Extensions"}
    ]
  end

  # Egyptian hieroglyphs button set - for the sophisticated coder!
  def egyptian_buttons() do
    [
      %{id: :new_file, glyph: "𓈒", tooltip: "New File"}, # Beginning/New
      %{id: :open_file, glyph: "𓊞", tooltip: "Open File"}, # Door/Open
      %{id: :save_file, glyph: "𓂋", tooltip: "Save File"}, # Preserve/Keep
      %{id: :search, glyph: "𓂀", tooltip: "Search"}, # Eye/See
      %{id: :settings, glyph: "𓊨", tooltip: "Settings"} # Tools/Craft
    ]
  end

  # Symbol buttons using Noto Sans Symbols
  def symbol_buttons() do
    [
      %{id: :new_file, glyph: "⊕", tooltip: "New File"}, # Plus in circle
      %{id: :open_file, glyph: "⊞", tooltip: "Open File"}, # Square plus
      %{id: :save_file, glyph: "⊡", tooltip: "Save File"}, # Square with dot
      %{id: :search, glyph: "⊗", tooltip: "Search"}, # Circle with X
      %{id: :settings, glyph: "⊙", tooltip: "Settings"} # Circle with dot
    ]
  end

  # Simple ASCII buttons (fallback)
  def ascii_buttons() do
    [
      %{id: :new_file, glyph: "+", tooltip: "New File"},
      %{id: :open_file, glyph: "O", tooltip: "Open File"},
      %{id: :save_file, glyph: "S", tooltip: "Save File"},
      %{id: :search, glyph: "?", tooltip: "Search"},
      %{id: :settings, glyph: "*", tooltip: "Settings"}
    ]
  end

  # Cool ASCII art buttons - creative combinations that work everywhere!
  def cool_ascii_buttons() do
    [
      %{id: :new_file, glyph: "[+]", tooltip: "New File"},
      %{id: :open_file, glyph: "{ }", tooltip: "Open File"},
      %{id: :save_file, glyph: "[=]", tooltip: "Save File"},
      %{id: :search, glyph: "(o)", tooltip: "Search"},
      %{id: :settings, glyph: "<*>", tooltip: "Settings"},
      %{id: :terminal, glyph: ">_", tooltip: "Terminal"},
      %{id: :git, glyph: "Y", tooltip: "Git Branch"}
    ]
  end

  # ASCII box drawing buttons - using box characters
  def box_ascii_buttons() do
    [
      %{id: :new_file, glyph: "┼", tooltip: "New File"},
      %{id: :open_file, glyph: "□", tooltip: "Open File"},
      %{id: :save_file, glyph: "▪", tooltip: "Save File"},
      %{id: :search, glyph: "◯", tooltip: "Search"},
      %{id: :settings, glyph: "◆", tooltip: "Settings"}
    ]
  end

  # Minimalist ASCII buttons - single powerful characters
  def minimal_ascii_buttons() do
    [
      %{id: :new_file, glyph: "↑", tooltip: "New File"},
      %{id: :open_file, glyph: "→", tooltip: "Open File"},
      %{id: :save_file, glyph: "↓", tooltip: "Save File"},
      %{id: :search, glyph: "◎", tooltip: "Search"},
      %{id: :settings, glyph: "≡", tooltip: "Settings"},
      %{id: :terminal, glyph: "$", tooltip: "Terminal"},
      %{id: :extensions, glyph: "⊞", tooltip: "Extensions"}
    ]
  end

  # Retro ASCII buttons - old school computer vibes
  def retro_ascii_buttons() do
    [
      %{id: :new_file, glyph: "▲", tooltip: "New File"},
      %{id: :open_file, glyph: "■", tooltip: "Open File"},
      %{id: :save_file, glyph: "●", tooltip: "Save File"},
      %{id: :search, glyph: "◊", tooltip: "Search"},
      %{id: :settings, glyph: "▼", tooltip: "Settings"}
    ]
  end

  # Emoji buttons - for when we dream of a more expressive future!
  def emoji_buttons() do
    [
      %{id: :new_file, glyph: "📄", tooltip: "New File"},
      %{id: :open_file, glyph: "📂", tooltip: "Open File"},
      %{id: :save_file, glyph: "💾", tooltip: "Save File"},
      %{id: :search, glyph: "🔍", tooltip: "Search"},
      %{id: :settings, glyph: "⚙️", tooltip: "Settings"},
      %{id: :favorite, glyph: "⭐", tooltip: "Favorites"},
      %{id: :home, glyph: "🏠", tooltip: "Home"}
    ]
  end

  # Private rendering functions
  defp render_ubuntu_bar(graph, state) do
    graph
    |> rect(
      {state.frame.size.width, state.frame.size.height},
      fill: state.background_color
    )
    |> render_buttons(state)
  end

  defp render_buttons(graph, state) do
    button_size = state.button_size
    button_spacing = state.button_spacing
    
    # Calculate consistent margin (same as side margin)
    side_margin = (state.frame.size.width - button_size) / 2
    
    # Calculate starting Y position based on layout
    total_height = length(state.buttons) * button_size + (length(state.buttons) - 1) * button_spacing
    
    start_y = case state.layout do
      :top -> 
        # Check if we should remove top margin for visual alignment
        if state.remove_top_margin do
          0
        else
          # Use same margin as sides for visual consistency
          side_margin
        end
      :center -> 
        max(0, (state.frame.size.height - total_height) / 2)
      :bottom -> 
        # Use same margin as sides for visual consistency
        state.frame.size.height - total_height - side_margin
    end
    
    Enum.with_index(state.buttons)
    |> Enum.reduce(graph, fn {button, index}, acc_graph ->
      y_pos = start_y + (index * (button_size + button_spacing))
      render_button(acc_graph, state, button, button_size, y_pos)
    end)
  end

  defp render_button(graph, state, button, button_size, y_pos) do
    is_active = state.active_button == button.id
    is_hovered = state.hovered_button == button.id
    
    # Center button horizontally in the frame with consistent margins
    # Use the same margin on all sides for visual harmony
    side_margin = (state.frame.size.width - button_size) / 2
    x_pos = side_margin
    
    button_color = cond do
      is_active -> state.button_active_color
      is_hovered -> state.button_hover_color
      true -> state.button_color
    end

    graph
    |> group(
      fn graph ->
        graph
        |> render_button_background(button, button_size, button_color)
        |> render_button_glyph(button, state, button_size)
      end,
      id: {:ubuntu_bar_button, button.id},
      translate: {x_pos, y_pos}
    )
  end

  defp render_button_background(graph, button, button_size, button_color) do
    graph
    |> rrect(
      {button_size, button_size, 4}, # width, height, radius
      id: {:button_bg, button.id},
      input: [:cursor_button, :cursor_pos],
      fill: button_color
    )
  end

  defp render_button_glyph(graph, button, state, button_size) do
    # Center the glyph in the button
    glyph_x = button_size / 2
    glyph_y = button_size / 2 + state.font_size / 3 # Adjust for text baseline
    
    # Build text options with optional font family
    text_opts = [
      font_size: state.font_size,
      fill: state.text_color,
      text_align: :center,
      translate: {glyph_x, glyph_y}
    ]
    
    # Add font family if specified
    text_opts = if state.font_family do
      [{:font, state.font_family} | text_opts]
    else
      text_opts
    end
    
    graph
    |> text(button.glyph, text_opts)
  end
end