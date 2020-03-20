defmodule Exampple.Saxy.Parser.Sender do
  @moduledoc false

  @behaviour Saxy.Handler

  alias Exampple.Saxy.Parser.Simple
  alias Exampple.Saxy.Xmlel

  defmodule Data do
    defstruct pid: nil, stack: [], debug_xml: false
  end

  def handle_event(:start_document, _prolog, pid) do
    debug_xml = Application.get_env(:exampple, :debug_xml, false)
    if debug_xml, do: send(pid, :xmlstartdoc)
    {:ok, %Data{pid: pid, debug_xml: debug_xml}}
  end

  def handle_event(:start_element, {tag_name, attributes}, data) do
    send(data.pid, {:xmlstreamstart, tag_name, attributes})
    {:ok, stack} = Simple.handle_event(:start_element, {tag_name, attributes}, data.stack)
    {:ok, %Data{data | stack: stack}}
  end

  def handle_event(:characters, chars, data) do
    if data.debug_xml, do: send(data.pid, {:xmlcdata, chars})
    {:ok, stack} = Simple.handle_event(:characters, chars, data.stack)
    {:ok, %Data{data | stack: stack}}
  end

  def handle_event(:end_element, tag_name, data) do
    if data.debug_xml, do: send(data.pid, {:xmlstreamend, tag_name})
    {:ok, stack} = Simple.handle_event(:end_element, tag_name, data.stack)

    case stack do
      [%Xmlel{name: ^tag_name} = xmlel] -> send(data.pid, {:xmlelement, xmlel})
      _ -> :ok
    end

    {:ok, %Data{data | stack: stack}}
  end

  def handle_event(:end_document, _, data) do
    if data.debug_xml, do: send(data.pid, :xmlenddoc)
    {:ok, data}
  end
end
