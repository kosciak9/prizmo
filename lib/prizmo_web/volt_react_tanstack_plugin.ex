defmodule PrizmoWeb.VoltReactTanstackPlugin do
  @moduledoc false

  @behaviour Volt.Plugin

  alias Volt.JS.PrebundleEntry.Export
  alias Volt.JS.PrebundleEntry.Import

  @build_mode_key {__MODULE__, :build_mode}

  @virtual_root Path.expand("lib/prizmo_web/spa/.volt_virtual/react_tanstack")

  @virtual_modules %{
    "react" => "react.js",
    "react-dom" => "react_dom.js",
    "react-dom/client" => "react_dom_client.js",
    "react/jsx-runtime" => "react_jsx_runtime.js",
    "react/jsx-dev-runtime" => "react_jsx_dev_runtime.js",
    "scheduler" => "scheduler.js",
    "use-sync-external-store/shim" => "use_sync_external_store_shim.js",
    "use-sync-external-store/shim/with-selector" => "use_sync_external_store_with_selector.js"
  }

  @prebundle_externals Map.keys(@virtual_modules) -- ["scheduler"]

  @react_exports ~w(
    Activity
    Children
    Component
    Fragment
    Profiler
    PureComponent
    StrictMode
    Suspense
    __CLIENT_INTERNALS_DO_NOT_USE_OR_WARN_USERS_THEY_CANNOT_UPGRADE
    __COMPILER_RUNTIME
    cache
    cacheSignal
    cloneElement
    createContext
    createElement
    createRef
    forwardRef
    isValidElement
    lazy
    memo
    startTransition
    unstable_useCacheRefresh
    use
    useActionState
    useCallback
    useContext
    useDebugValue
    useDeferredValue
    useEffect
    useEffectEvent
    useId
    useImperativeHandle
    useInsertionEffect
    useLayoutEffect
    useMemo
    useOptimistic
    useReducer
    useRef
    useState
    useSyncExternalStore
    useTransition
    version
  )

  @react_dom_exports ~w(
    __DOM_INTERNALS_DO_NOT_USE_OR_WARN_USERS_THEY_CANNOT_UPGRADE
    createPortal
    flushSync
    preconnect
    prefetchDNS
    preinit
    preinitModule
    preload
    preloadModule
    requestFormReset
    unstable_batchedUpdates
    useFormState
    useFormStatus
    version
  )

  @react_dom_client_exports ~w(
    createRoot
    hydrateRoot
    version
  )

  @jsx_runtime_exports ~w(
    Fragment
    jsx
    jsxs
  )

  @jsx_dev_runtime_exports ~w(
    Fragment
    jsxDEV
  )

  @scheduler_exports ~w(
    unstable_now
    unstable_IdlePriority
    unstable_ImmediatePriority
    unstable_LowPriority
    unstable_NormalPriority
    unstable_Profiling
    unstable_UserBlockingPriority
    unstable_cancelCallback
    unstable_forceFrameRate
    unstable_getCurrentPriorityLevel
    unstable_next
    unstable_requestPaint
    unstable_runWithPriority
    unstable_scheduleCallback
    unstable_shouldYield
    unstable_wrapCallback
  )

  @impl true
  def name, do: "react-tanstack"

  @impl true
  def enforce, do: :pre

  @impl true
  def define(mode) do
    mode = to_string(mode)
    Process.put(@build_mode_key, mode)

    %{
      "process.env.NODE_ENV" => inspect(mode),
      "process.env.DEBUG" => "undefined",
      "process.env.TSS_INLINE_CSS_ENABLED" => "undefined"
    }
  end

  @impl true
  def resolve(specifier, _importer) do
    case Map.fetch(@virtual_modules, specifier) do
      {:ok, filename} -> {:ok, Path.join(@virtual_root, filename)}
      :error -> nil
    end
  end

  @impl true
  def load(path) do
    {path, _query} = Volt.URL.split_query(path)

    with {:ok, specifier} <- virtual_specifier(path),
         {:ok, source} <- virtual_source(specifier) do
      {:ok, source, "application/javascript"}
    else
      :error -> nil
    end
  end

  @impl true
  def transform(code, _path) do
    if String.contains?(code, "process.env.") do
      {:ok, rewrite_process_env(code)}
    else
      {:ok, code}
    end
  end

  @impl true
  def prebundle_externals, do: @prebundle_externals

  @impl true
  def prebundle_alias("react-dom"), do: "react"
  def prebundle_alias("react-dom/client"), do: "react"
  def prebundle_alias("react/jsx-runtime"), do: "react"
  def prebundle_alias("react/jsx-dev-runtime"), do: "react"
  def prebundle_alias("use-sync-external-store/shim"), do: "react"
  def prebundle_alias("use-sync-external-store/shim/with-selector"), do: "react"
  def prebundle_alias(_specifier), do: nil

  @impl true
  def prebundle_entry("react") do
    {:proxy, "react.js",
     imports: [Import.default("React", from: "react")],
     exports: [
       Export.default("React"),
       Export.members(Enum.map(@react_exports, &{&1, "React.#{&1}"})),
       Export.named_from(
         "react-dom",
         Enum.reject(@react_dom_exports, &(&1 == "version")) ++ [{"version", "reactDomVersion"}]
       ),
       Export.named_from("react-dom/client", [
         "createRoot",
         "hydrateRoot",
         {"version", "reactDomClientVersion"}
       ]),
       Export.named_from(
         "react/jsx-runtime",
         Enum.reject(@jsx_runtime_exports, &(&1 == "Fragment"))
       ),
       Export.named_from(
         "react/jsx-dev-runtime",
         Enum.reject(@jsx_dev_runtime_exports, &(&1 == "Fragment"))
       ),
       Export.named_from("use-sync-external-store/shim/with-selector", [
         "useSyncExternalStoreWithSelector"
       ])
     ]}
  end

  def prebundle_entry(_specifier), do: nil

  defp virtual_specifier(path) do
    normalized_path = Path.expand(path)

    Enum.find_value(@virtual_modules, :error, fn {specifier, filename} ->
      if normalized_path == Path.join(@virtual_root, filename) do
        {:ok, specifier}
      end
    end)
  end

  defp virtual_source("react") do
    react_source("react/cjs/react.production.js", @react_exports)
  end

  defp virtual_source("react-dom") do
    react_source("react-dom/cjs/react-dom.production.js", @react_dom_exports, [
      {"react", "__volt_react"}
    ])
  end

  defp virtual_source("react-dom/client") do
    react_source("react-dom/cjs/react-dom-client.production.js", @react_dom_client_exports, [
      {"scheduler", "__volt_scheduler"},
      {"react", "__volt_react"},
      {"react-dom", "__volt_react_dom"}
    ])
  end

  defp virtual_source("react/jsx-runtime") do
    react_source("react/cjs/react-jsx-runtime.production.js", @jsx_runtime_exports)
  end

  defp virtual_source("react/jsx-dev-runtime") do
    react_source("react/cjs/react-jsx-dev-runtime.production.js", @jsx_dev_runtime_exports)
  end

  defp virtual_source("scheduler") do
    react_source("scheduler/cjs/scheduler.production.js", @scheduler_exports)
  end

  defp virtual_source("use-sync-external-store/shim") do
    react_source(
      "use-sync-external-store/cjs/use-sync-external-store-shim.production.js",
      ["useSyncExternalStore"],
      [{"react", "__volt_react"}]
    )
  end

  defp virtual_source("use-sync-external-store/shim/with-selector") do
    react_source(
      "use-sync-external-store/cjs/use-sync-external-store-shim/with-selector.production.js",
      ["useSyncExternalStoreWithSelector"],
      [{"react", "__volt_react"}, {"use-sync-external-store/shim", "__volt_shim"}]
    )
  end

  defp virtual_source(_specifier), do: :error

  # sobelow_skip ["Traversal.FileModule"]
  defp react_source(package_path, exports, imports \\ []) do
    node_module_source_path = node_module_path(package_path)

    node_module_source_path
    |> File.read!()
    |> rewrite_commonjs_requires(imports)
    |> wrap_commonjs_as_esm(exports, imports)
    |> then(&{:ok, &1})
  end

  defp node_module_path(package_path) do
    Path.expand("node_modules/#{package_path}")
  end

  defp rewrite_commonjs_requires(source, imports) do
    Enum.reduce(imports, source, fn {specifier, binding}, code ->
      code
      |> String.replace("require(\"#{specifier}\")", binding)
      |> String.replace("require('#{specifier}')", binding)
      |> String.replace("require(`#{specifier}`)", binding)
    end)
  end

  defp wrap_commonjs_as_esm(source, exports, imports) do
    import_lines =
      Enum.map_join(imports, "\n", fn {specifier, binding} ->
        "import #{binding} from #{inspect(specifier)};"
      end)

    named_exports =
      Enum.map_join(exports, "\n", fn export ->
        binding = "__volt_commonjs_export_#{export}"

        "const #{binding} = __volt_commonjs_exports[#{inspect(export)}];\n" <>
          "export { #{binding} as #{export} };"
      end)

    IO.iodata_to_binary([
      import_lines,
      "\nvar __volt_commonjs_initial_exports = {};\n",
      "var module = { exports: __volt_commonjs_initial_exports };\n",
      "var exports = module.exports;\n",
      source,
      "\nvar __volt_commonjs_exports = module.exports;\n",
      "export default __volt_commonjs_exports;\n",
      named_exports,
      "\n"
    ])
  end

  defp rewrite_process_env(code) do
    node_env = Process.get(@build_mode_key, "development")

    code
    |> then(&Regex.replace(~r/\bprocess\.env\.NODE_ENV\b/, &1, inspect(node_env)))
    |> then(&Regex.replace(~r/\bprocess\.env\.[A-Za-z_$][A-Za-z0-9_$]*\b/, &1, "undefined"))
  end
end
