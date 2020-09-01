defmodule Exampple.Router do
  require Logger

  alias Exampple.Xml.Xmlel

  @dynsup Exampple.Router.Task.Monitor.Supervisor
  @monitor Exampple.Router.Task.Monitor
  @default_timeout 5_000

  def route(xmlel, domain, otp_app, timeout \\ @default_timeout) do
    Logger.debug("[router] processing: #{inspect(xmlel)}")
    DynamicSupervisor.start_child(@dynsup, {@monitor, [xmlel, domain, otp_app, timeout]})
  end

  defmacro __using__(_opts) do
    quote do
      import Exampple.Router
      Module.register_attribute(__MODULE__, :routes, accumulate: true)
      Module.register_attribute(__MODULE__, :namespaces, accumulate: true)
      Module.register_attribute(__MODULE__, :identities, accumulate: true)
      @envelopes []
      @before_compile Exampple.Router
    end
  end

  defmacro __before_compile__(env) do
    routes = Module.get_attribute(env.module, :routes)
    envelopes = Module.get_attribute(env.module, :envelopes)
    disco = Module.get_attribute(env.module, :disco, false)

    route_functions =
      for route <- routes do
        {{stanza_type, type, xmlns, controller, function}, []} = Code.eval_quoted(route)

        quote do
          def route(
                %Exampple.Router.Conn{
                  stanza_type: unquote(stanza_type),
                  xmlns: unquote(xmlns),
                  type: unquote(type)
                } = conn,
                stanza
              ) do
            unquote(controller).unquote(function)(conn, stanza)
          end
        end
      end

    fallback =
      if fback = Module.get_attribute(env.module, :fallback) do
        {{controller, function}, []} = Code.eval_quoted(fback)

        [
          quote do
            def route(conn, stanza), do: unquote(controller).unquote(function)(conn, stanza)
          end
        ]
      else
        []
      end

    envelope_functions =
      for envelope_xmlns <- envelopes do
        quote do
          def route(
                %Exampple.Router.Conn{
                  xmlns: unquote(envelope_xmlns)
                } = conn,
                stanza
              ) do
            case Exampple.Xmpp.Envelope.handle(conn, stanza) do
              {conn, stanza} -> route(conn, stanza)
              nil -> :ok
            end
          end
        end
      end

    namespaces =
      for ns <- Enum.uniq(Module.get_attribute(env.module, :namespaces)), ns != "", do: ns

    disco_info =
      if disco do
        namespaces =
          for namespace <- namespaces do
            Macro.escape(Xmlel.new("feature", %{"var" => namespace}))
          end

        identity =
          for identity <- Module.get_attribute(env.module, :identities) do
            {{category, type, name}, []} = Code.eval_quoted(identity)
            Macro.escape(Xmlel.new("identity", %{
              "category" => category,
              "type" => type,
              "name" => name
            }))
          end

        identity ++ namespaces
      else
        []
      end

    discovery =
      quote do
        def route(
              %Exampple.Router.Conn{
                xmlns: "http://jabber.org/protocol/disco#info"
              } = conn,
              [stanza]
            ) do
          payload = %Xmlel{stanza | children: unquote(disco_info)}
          conn
          |> Exampple.Xmpp.Stanza.iq_resp([payload])
          |> Exampple.Component.send()
        end
      end

    route_info_function =
      quote do
        def route_info(:paths), do: unquote(routes)
        def route_info(:namespaces), do: unquote(namespaces)
      end

    [route_info_function | envelope_functions] ++ route_functions ++ [discovery] ++ [fallback]
  end

  defmacro envelope(xmlns) do
    xmlns_list = if is_list(xmlns), do: xmlns, else: [xmlns]

    quote location: :keep do
      xmlns_list = unquote(xmlns_list)
      Module.put_attribute(__MODULE__, :envelopes, xmlns_list)
      for xmlns <- xmlns_list do
        Module.put_attribute(__MODULE__, :namespaces, xmlns)
      end
    end
  end

  defmacro iq(xmlns_partial \\ "", do: block) do
    quote location: :keep do
      Module.put_attribute(__MODULE__, :stanza_type, "iq")
      Module.put_attribute(__MODULE__, :xmlns_partial, unquote(xmlns_partial))
      unquote(block)
    end
  end

  defmacro message(xmlns_partial \\ "", do: block) do
    quote location: :keep do
      Module.put_attribute(__MODULE__, :stanza_type, "message")
      Module.put_attribute(__MODULE__, :xmlns_partial, unquote(xmlns_partial))
      unquote(block)
    end
  end

  defmacro presence(xmlns_partial \\ "", do: block) do
    quote location: :keep do
      Module.put_attribute(__MODULE__, :stanza_type, "presence")
      Module.put_attribute(__MODULE__, :xmlns_partial, unquote(xmlns_partial))
      unquote(block)
    end
  end

  def validate_controller!(controller) do
    {module, []} = Code.eval_quoted(controller)

    try do
      module.module_info()
    rescue
      UndefinedFunctionError ->
        module_name =
          module
          |> Module.split()
          |> Enum.join(".")

        raise ArgumentError, """
        \nThe module #{module_name} was not found to create the route,
        use absolute paths or aliases to be sure all of the modules
        are reachable.
        """
    end
  end

  def validate_function!(controller, function) do
    {module, []} = Code.eval_quoted(controller)
    {function, []} = Code.eval_quoted(function)

    unless function_exported?(module, function, 2) do
      module_name =
        module
        |> Module.split()
        |> Enum.join(".")

      raise ArgumentError, """
      \nThe function #{module_name}.#{function}/2 was not found to create
      the route, check the function exists and have 2 parameters to
      receive "conn" and "stanza".
      """
    end
  end

  defmacro discovery(block \\ nil) do
    if block do
      quote do
        Module.put_attribute(__MODULE__, :disco, true)
        unquote(block)
      end
    else
      quote do
        Module.put_attribute(__MODULE__, :disco, true)
      end
    end
  end

  defmacro identity(opts) do
    quote do
      opts = unquote(opts)
      unless Module.get_attribute(__MODULE__, :disco, false) do
        raise """
        identity MUST be inside of a discovery block.
        """
      end
      unless category = opts[:category] do
        raise """
        identity MUST contain a category option.
        """
      end
      unless type = opts[:type] do
        raise """
        identity MUST contain a type option.
        """
      end
      unless name = opts[:name] do
        raise """
        identity MUST contain a name option.
        """
      end
      Module.put_attribute(__MODULE__, :identities, Macro.escape({category, type, name}))
    end
  end

  defmacro error(xmlns \\ "", controller, function) do
    validate_controller!(controller)
    validate_function!(controller, function)

    quote location: :keep do
      Module.put_attribute(
        __MODULE__,
        :routes,
        Macro.escape(
          {@stanza_type, "error", @xmlns_partial <> unquote(xmlns), unquote(controller),
           unquote(function)}
        )
      )
      Module.put_attribute(__MODULE__, :namespaces, @xmlns_partial <> unquote(xmlns))
    end
  end

  defmacro unavailable(xmlns \\ "", controller, function) do
    validate_controller!(controller)
    validate_function!(controller, function)

    quote location: :keep do
      Module.put_attribute(
        __MODULE__,
        :routes,
        Macro.escape(
          {@stanza_type, "unavailable", @xmlns_partial <> unquote(xmlns), unquote(controller),
           unquote(function)}
        )
      )
      Module.put_attribute(__MODULE__, :namespaces, @xmlns_partial <> unquote(xmlns))
    end
  end

  defmacro subscribe(xmlns \\ "", controller, function) do
    validate_controller!(controller)
    validate_function!(controller, function)

    quote location: :keep do
      Module.put_attribute(
        __MODULE__,
        :routes,
        Macro.escape(
          {@stanza_type, "subscribe", @xmlns_partial <> unquote(xmlns), unquote(controller),
           unquote(function)}
        )
      )
      Module.put_attribute(__MODULE__, :namespaces, @xmlns_partial <> unquote(xmlns))
    end
  end

  defmacro subscribed(xmlns \\ "", controller, function) do
    validate_controller!(controller)
    validate_function!(controller, function)

    quote location: :keep do
      Module.put_attribute(
        __MODULE__,
        :routes,
        Macro.escape(
          {@stanza_type, "subscribed", @xmlns_partial <> unquote(xmlns), unquote(controller),
           unquote(function)}
        )
      )
      Module.put_attribute(__MODULE__, :namespaces, @xmlns_partial <> unquote(xmlns))
    end
  end

  defmacro unsubscribe(xmlns \\ "", controller, function) do
    validate_controller!(controller)
    validate_function!(controller, function)

    quote location: :keep do
      Module.put_attribute(
        __MODULE__,
        :routes,
        Macro.escape(
          {@stanza_type, "unsubscribe", @xmlns_partial <> unquote(xmlns), unquote(controller),
           unquote(function)}
        )
      )
      Module.put_attribute(__MODULE__, :namespaces, @xmlns_partial <> unquote(xmlns))
    end
  end

  defmacro unsubscribed(xmlns \\ "", controller, function) do
    validate_controller!(controller)
    validate_function!(controller, function)

    quote location: :keep do
      Module.put_attribute(
        __MODULE__,
        :routes,
        Macro.escape(
          {@stanza_type, "unsubscribed", @xmlns_partial <> unquote(xmlns), unquote(controller),
           unquote(function)}
        )
      )
      Module.put_attribute(__MODULE__, :namespaces, @xmlns_partial <> unquote(xmlns))
    end
  end

  defmacro probe(xmlns \\ "", controller, function) do
    validate_controller!(controller)
    validate_function!(controller, function)

    quote location: :keep do
      Module.put_attribute(
        __MODULE__,
        :routes,
        Macro.escape(
          {@stanza_type, "probe", @xmlns_partial <> unquote(xmlns), unquote(controller),
           unquote(function)}
        )
      )
      Module.put_attribute(__MODULE__, :namespaces, @xmlns_partial <> unquote(xmlns))
    end
  end

  defmacro normal(xmlns \\ "", controller, function) do
    validate_controller!(controller)
    validate_function!(controller, function)

    quote location: :keep do
      Module.put_attribute(
        __MODULE__,
        :routes,
        Macro.escape(
          {@stanza_type, "normal", @xmlns_partial <> unquote(xmlns), unquote(controller),
           unquote(function)}
        )
      )
      Module.put_attribute(__MODULE__, :namespaces, @xmlns_partial <> unquote(xmlns))
    end
  end

  defmacro headline(xmlns \\ "", controller, function) do
    validate_controller!(controller)
    validate_function!(controller, function)

    quote location: :keep do
      Module.put_attribute(
        __MODULE__,
        :routes,
        Macro.escape(
          {@stanza_type, "headline", @xmlns_partial <> unquote(xmlns), unquote(controller),
           unquote(function)}
        )
      )
      Module.put_attribute(__MODULE__, :namespaces, @xmlns_partial <> unquote(xmlns))
    end
  end

  defmacro groupchat(xmlns \\ "", controller, function) do
    validate_controller!(controller)
    validate_function!(controller, function)

    quote location: :keep do
      Module.put_attribute(
        __MODULE__,
        :routes,
        Macro.escape(
          {@stanza_type, "groupchat", @xmlns_partial <> unquote(xmlns), unquote(controller),
           unquote(function)}
        )
      )
      Module.put_attribute(__MODULE__, :namespaces, @xmlns_partial <> unquote(xmlns))
    end
  end

  defmacro chat(xmlns \\ "", controller, function) do
    validate_controller!(controller)
    validate_function!(controller, function)

    quote location: :keep do
      Module.put_attribute(
        __MODULE__,
        :routes,
        Macro.escape(
          {@stanza_type, "chat", @xmlns_partial <> unquote(xmlns), unquote(controller),
           unquote(function)}
        )
      )
      Module.put_attribute(__MODULE__, :namespaces, @xmlns_partial <> unquote(xmlns))
    end
  end

  defmacro get(xmlns, controller, function) do
    validate_controller!(controller)
    validate_function!(controller, function)

    quote location: :keep do
      Module.put_attribute(
        __MODULE__,
        :routes,
        Macro.escape(
          {@stanza_type, "get", @xmlns_partial <> unquote(xmlns), unquote(controller),
           unquote(function)}
        )
      )
      Module.put_attribute(__MODULE__, :namespaces, @xmlns_partial <> unquote(xmlns))
    end
  end

  defmacro set(xmlns, controller, function) do
    validate_controller!(controller)
    validate_function!(controller, function)

    quote location: :keep do
      Module.put_attribute(
        __MODULE__,
        :routes,
        Macro.escape(
          {@stanza_type, "set", @xmlns_partial <> unquote(xmlns), unquote(controller),
           unquote(function)}
        )
      )
      Module.put_attribute(__MODULE__, :namespaces, @xmlns_partial <> unquote(xmlns))
    end
  end

  defmacro fallback(controller, function) do
    validate_controller!(controller)
    validate_function!(controller, function)

    quote location: :keep do
      Module.put_attribute(
        __MODULE__,
        :fallback,
        Macro.escape({unquote(controller), unquote(function)})
      )
    end
  end
end
