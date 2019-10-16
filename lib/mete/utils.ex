defmodule Mete.Utils do
  @moduledoc false
  def into_tags([], tags), do: tags
  def into_tags(keyword, tags), do: into_tags(keyword, [], tags)

  def into_tags([{key, nil} | keyword], prepend, tags) do
    into_tags(keyword, prepend, :lists.keydelete(key, 1, tags))
  end

  def into_tags([{key, _} = pair | keyword], prepend, tags) do
    into_tags(keyword, [pair | prepend], :lists.keydelete(key, 1, tags))
  end

  def into_tags([], prepend, tags) do
    prepend ++ tags
  end
end
