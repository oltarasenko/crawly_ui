defmodule CrawlyUIWeb.ScheduleLive do
  use Phoenix.LiveView, layout: {CrawlyUIWeb.LayoutView, "live.html"}

  def render(%{template: template} = assigns) do
    CrawlyUIWeb.JobView.render(template, assigns)
  end

  def mount(%{"node" => node}, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :pick_spider, 1000)

    node = String.to_atom(node)
    spiders = :rpc.call(node, Crawly, :list_spiders, [])

    {:ok, assign(socket, template: "pick_spider.html", node: node, spiders: spiders, error: nil)}
  end

  def mount(_param, _session, socket) do
    nodes = Node.list()
    if connected?(socket), do: Process.send_after(self(), :pick_node, 100)
    {:ok, assign(socket, template: "pick_node.html", nodes: nodes)}
  end

  def handle_info(:pick_node, socket) do
    nodes = Node.list()
    if connected?(socket), do: Process.send_after(self(), :pick_node, 1000)
    {:noreply, assign(socket, nodes: nodes)}
  end

  def handle_info(:pick_spider, socket) do
    if connected?(socket), do: Process.send_after(self(), :pick_spider, 1000)

    node = socket.assigns.node
    spiders = :rpc.call(node, Crawly, :list_spiders, [])

    {:noreply, assign(socket, spiders: spiders)}
  end

  def handle_event("spider_picked", %{"node" => node}, socket) do
    {:noreply,
     redirect(socket,
       to: CrawlyUIWeb.Router.Helpers.schedule_path(socket, :pick_spider, node: node)
     )}
  end

  def handle_event("schedule_spider", %{"spider" => spider}, socket) do
    node_atom = socket.assigns.node
    spider_atom = String.to_atom(spider)

    node = to_string(node_atom)

    uuid = Ecto.UUID.generate()

    case :rpc.call(node_atom, Crawly.Engine, :start_spider, [spider_atom, uuid]) do
      :ok ->
        {:ok, _} =
          CrawlyUI.Manager.create_job(%{spider: spider, tag: uuid, state: "new", node: node})

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Spider scheduled successfully. It might take a bit of time before items will appear here..."
         )
         |> push_redirect(to: CrawlyUIWeb.Router.Helpers.job_path(socket, :index))}

      error ->
        {:noreply,
         socket
         |> put_flash(:error, "#{inspect(error)}")
         |> push_redirect(to: CrawlyUIWeb.Router.Helpers.schedule_path(socket, :pick_node))}
    end
  end
end
