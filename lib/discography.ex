defmodule Discography do
  def main(name) do
    id = Discography.create_board(name)
    Discography.create_list_and_cards(id)
    :ok
  end

  def create_board(name) do
    {:ok, %{id: id} = _res} = Discography.make_trello_request("boards", :post, %{name: name})
    id
  end

  def create_list_and_cards(id) do
    decades = Enum.reverse(Discography.sort_discography())
    board_id = id

    Enum.each(decades, fn decade ->
      %{album: album} = _first = List.first(decade)
      name = "#{String.slice(album, 0..2)}0"

      {:ok, %{id: list_id} = _res} =
        Discography.make_trello_request("lists", :post, %{name: name, idBoard: board_id})

      Enum.each(decade, fn album ->
        %{album: name, image: image} = album

        {:ok, %{id: card_id} = _res} =
          Discography.make_trello_request("cards", :post, %{name: name, idList: list_id})

        Discography.make_trello_request("cards/#{card_id}/attachments", :post, %{url: image})
      end)
    end)
  end

  def sort_discography do
    {:ok, contents} = File.read("discography.txt")
    albums = contents |> String.split("\n", trim: true)
    sorted_albums = Enum.sort(albums)
    token = Discography.spotify_request_token()

    albums_with_image =
      Enum.map(sorted_albums, fn x ->
        %{album: x, image: Discography.get_spotify_images(x, token)}
      end)

    albums_by_decade =
      Enum.sort(Map.values(Enum.group_by(albums_with_image, &String.slice(&1.album, 2..2))))

    albums_by_decade
  end

  def make_trello_request(type, method, query) do
    key = Application.fetch_env!(:discography, :trello_api_key)
    token = Application.fetch_env!(:discography, :trello_api_token)
    options = [params: Map.merge(%{key: key, token: token}, query)]
    url = "https://api.trello.com/1/#{type}"
    method = method
    {:ok, res} = HTTPoison.request(method, url, "", [], options)
    Poison.decode(res.body, keys: :atoms)
  end

  def get_spotify_images(query, token) do
    headers = [Authorization: "Bearer #{token}", "Content-Type": "application/json"]
    options = [params: %{q: "#{query}%20bob%20dylan", type: "album", limit: 1}]
    url = "https://api.spotify.com/v1/search"
    method = :get
    {:ok, res} = HTTPoison.request(method, url, "", headers, options)
    {:ok, res} = Poison.decode(res.body, keys: :atoms)
    first = List.first(res.albums.items)

    if first do
      [%{url: url} | _rest] = first.images
      url
    else
      ""
    end
  end

  def spotify_request_token do
    client_id = Application.fetch_env!(:discography, :spotify_client_id)
    client_secret = Application.fetch_env!(:discography, :spotify_client_secret)
    url = "https://accounts.spotify.com/api/token"

    headers = [
      Authorization: "Basic #{Base.encode64("#{client_id}:#{client_secret}")}",
      "Content-Type": "application/x-www-form-urlencoded"
    ]

    body = {:form, [grant_type: "client_credentials"]}
    options = [json: true]
    {:ok, res} = HTTPoison.request(:post, url, body, headers, options)
    {:ok, res} = Poison.decode(res.body, keys: :atoms)
    res.access_token
  end
end
