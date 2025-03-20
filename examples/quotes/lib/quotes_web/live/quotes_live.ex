defmodule QuotesWeb.QuotesLive do
  use Phoenix.LiveView
  use LiveServerActions

  alias LiveServerActions.Components

  @quotes_database %{
    "pineapple" => [
      "Like the tough exterior of a pineapple, our challenges shape us, but they cannot define us – for within lies sweetness and strength.",
      "Life is like a pineapple upside-down cake - messy, imperfect, yet beautifully transformed by the heat of our experiences.",
      "Just as the pineapple plant grows new fruit from its own crown, may you cultivate resilience, renewal, and growth from within, rising stronger with each new challenge."
    ],
    "pear" => [
      "Just as a pear ripens with time, so too do our experiences shape us into the best version of ourselves.",
      "Life is like a pear tree - it requires patience, nurturing, and trust that the sweetness will come.",
      "Just as the tender skin of a pear protects the treasure within, may your resilience shield your heart and soul, allowing your true beauty to shine."
    ],
    "apple" => [
      "Like an apple seed, our smallest actions hold the potential to grow into something extraordinary.",
      "Life is like biting into a crisp apple - unexpected, refreshing, and full of hidden sweetness.",
      "Just as an apple tree blossoms in seasons of change, may you find strength in transformation and beauty in every stage of life."
    ]
  }

  @authors [
    "Mark Twain",
    "Jane Austen",
    "William Shakespeare",
    "Charles Dickens",
    "Ernest Hemingway",
    "F. Scott Fitzgerald",
    "George Orwell",
    "J.K. Rowling",
    "Agatha Christie",
    "J.R.R. Tolkien"
  ]

  def render(assigns) do
    ~H"""
    <Components.react_component id="my-fruit-quoter" component="RandomQuoteChooser" />
    """
  end

  @server_action true
  @spec get_quote(Phoenix.LiveView.Socket.t(), %{fruit: String.t()}) ::
          %{error: String.t()}
          | %{quote: String.t(), author: String.t(), year: integer()}
  defp get_quote(_socket, %{fruit: fruit}) do
    fruit = String.downcase(fruit)

    # artifical delay to simulate server response time
    :timer.sleep(1000)

    if Map.has_key?(@quotes_database, fruit) do
      %{
        quote: Enum.random(@quotes_database[fruit]),
        author: Enum.random(@authors),
        year: Enum.random(1000..2024)
      }
    else
      %{error: "I don't have any quotes for that fruit."}
    end
  end
end
