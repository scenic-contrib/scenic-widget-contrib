defmodule Mix.Tasks.WidgexNeo do
  use Mix.Task

  @shortdoc "Generates a new component with the standard structure."

  def run([name]) do
    component_path = "lib/#{name}"

    # Create the main directory for the component
    File.mkdir_p!(component_path)

    # Create the four files for the component
    create_file("#{component_path}/#{name}.ex", main_module(name))
    create_file("#{component_path}/#{name}_cmpnt.ex", cmpnt_module(name))
    create_file("#{component_path}/#{name}_state.ex", state_module(name))
    create_file("#{component_path}/#{name}_utils.ex", utils_module(name))

    Mix.shell().info("Component #{name} created successfully!")
  end

  defp create_file(path, content) do
    File.write!(path, content)
  end

  defp main_module(name) do
    """
    defmodule #{name} do
      @moduledoc "Main module for the #{name} component."
      # Your code here
    end
    """
  end

  def cmpnt_module(name) do
    ~s/
    defmodule #{name}Cmpnt do
      @moduledoc """
      A description of the #{name}Cmpnt and its purpose goes here.
      """

      use Scenic.Component
      alias YourApp.#{name}.State
      alias Widgex.Structs.{Frame, Coordinates, Dimensions}
      require Logger

      # Validation function
      def validate(%{
        frame: %Frame{} = f,
        state: %State{} = s
      }) do
        {:ok, {f, s}}
      end

      # Initialization function
      @spec init(Scenic.Scene.t(), {Frame.t(), State.t()}, list()) :: {:ok, Scenic.Scene.t()}
      def init(%Scenic.Scene{} = scene, {frame, state}, _opts) do
        init_graph = render(frame, state)

        init_scene =
          scene
          |> assign(state: state)
          |> assign(frame: frame)
          |> assign(graph: init_graph)
          |> push_graph(init_graph)

        {:ok, init_scene}
      end

      # Render function
      @doc """
      Rendering function for the #{name}Cmpnt.
      """
      @spec render(Frame.t(), State.t()) :: Scenic.Graph.t()
      def render(%Frame{} = frame, %State{} = state) do
        Scenic.Graph.build()
        # Add the rendering logic for the frame and state
      end

      # Handle various cast messages (Optional)
      def handle_cast(your_action, scene) do
        # Handle the specific action here
      end

      # Handle information messages (Optional)
      def handle_info(your_info, scene) do
        # Handle the specific information here
      end

      # Handle inputs (Optional)
      def handle_input(your_input, _context, scene) do
        # Handle the specific input here
      end
    end
    /
  end

  defp state_module(name) do
    ~s/
    defmodule YourApp.#{name}State do
      @moduledoc """
      Defines the internal state of a #{name}.

      This struct holds various attributes that determine the current state of a #{name}, including its rotation, animation status, and any related timer. Additionally, it includes various configuration settings such as primary color, animation rate, sizes, and mathematical constants.

      ## Fields

      - Add the specific attributes and their descriptions here.

      """

      @type t :: %__MODULE__{
              # Add specific fields here, similar to the following examples:
              rotation: float(),
              animate?: boolean(),
              timer: term(),
              # More fields as needed
            }

      defstruct [
        # Add default values for fields here
        rotation: 0,
        animate?: false
        # More defaults as needed
      ]

      @spec new(map()) :: t()
      def new(attrs \\ %{}) do
        # Construct a new state, potentially with default values
        %__MODULE__{ attrs | #default values here }
      end

      # Add other state-related functions here, such as:
      def cast(%__MODULE__{} = state, :tick) do
        # Compute any changes needed for a specific event, e.g., :tick
        # ...
      end

      # More functions as needed
    end
    /
  end

  defp utils_module(name) do
    """
    defmodule #{name}Utils do
      @moduledoc "Utility functions for #{name}."
      # Your code here
    end
    """
  end
end
