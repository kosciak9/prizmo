defmodule Mix.Tasks.Check.ServiceImages do
  @shortdoc "Checks service image pins match between local compose and CI"
  @moduledoc """
  Checks Docker service image pins are identical between local compose services
  and GitHub Actions services.
  """

  use Mix.Task

  @compose_file "local/compose.yml"
  @workflow_file ".github/workflows/elixir-build-and-test.yml"
  @service_mappings [{"db", "db"}, {"s3", "seaweedfs"}]

  @impl Mix.Task
  def run(_args) do
    mismatches =
      @service_mappings
      |> Enum.map(&service_image_comparison/1)
      |> Enum.reject(&matching_images?/1)

    case mismatches do
      [] -> :ok
      mismatches -> Mix.raise(mismatch_message(mismatches))
    end
  end

  defp service_image_comparison({compose_service, workflow_service}) do
    %{
      compose_service: compose_service,
      workflow_service: workflow_service,
      compose_image: image_for_service!(@compose_file, compose_service),
      workflow_image: image_for_service!(@workflow_file, workflow_service)
    }
  end

  defp image_for_service!(file, service) do
    file
    |> File.read!()
    |> String.split("\n")
    |> service_block(service)
    |> image_from_block(file, service)
  end

  defp service_block(lines, service) do
    service_index = Enum.find_index(lines, &(String.trim(&1) == "#{service}:"))

    if is_nil(service_index), do: Mix.raise("Could not find service #{inspect(service)}")

    service_indent = lines |> Enum.at(service_index) |> indentation()

    lines
    |> Enum.drop(service_index + 1)
    |> Enum.take_while(fn line ->
      String.trim(line) == "" or indentation(line) > service_indent
    end)
  end

  defp image_from_block(block, file, service) do
    case Enum.find_value(block, &image_line/1) do
      nil -> Mix.raise("Could not find image for service #{inspect(service)} in #{file}")
      image -> image
    end
  end

  defp image_line(line) do
    line = String.trim(line)

    if String.starts_with?(line, "image:"),
      do: line |> String.replace_prefix("image:", "") |> String.trim()
  end

  defp indentation(line), do: String.length(line) - String.length(String.trim_leading(line))
  defp matching_images?(%{compose_image: image, workflow_image: image}), do: true
  defp matching_images?(_comparison), do: false

  defp mismatch_message(mismatches) do
    mismatches
    |> Enum.flat_map(fn mismatch ->
      [
        "Service image pin mismatch for #{mismatch.compose_service}/#{mismatch.workflow_service}:",
        "  #{@compose_file}: #{mismatch.compose_image}",
        "  #{@workflow_file}: #{mismatch.workflow_image}"
      ]
    end)
    |> Enum.join("\n")
  end
end
