defmodule ExPlasma.Output.Type.Fee do
  @moduledoc """
  Fee Output Type.
  """

  alias ExPlasma.Output.Type.GenericPayment

  defdelegate to_rlp(output), to: GenericPayment

  defdelegate to_map(rlp), to: GenericPayment

  defdelegate validate(output), to: GenericPayment
end