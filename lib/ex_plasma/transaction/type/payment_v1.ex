defmodule ExPlasma.Transaction.Type.PaymentV1 do
  @moduledoc """
  Internal representation of a raw payment transaction done on Plasma chain.

  This module holds the representation of a "raw" transaction, i.e. without signatures nor recovered input spenders
  """
  alias ExPlasma.Crypto
  alias ExPlasma.Output
  alias ExPlasma.Transaction.TypeMapper

  @empty_metadata <<0::256>>
  @empty_tx_data 0
  @tx_type TypeMapper.tx_type_for(:tx_payment_v1)
  @output_type TypeMapper.output_type_for(:output_payment_v1)

  defstruct tx_type: @tx_type, inputs: [], outputs: [], tx_data: @empty_tx_data, metadata: @empty_metadata

  @type t() :: %__MODULE__{
          tx_type: pos_integer(),
          inputs: outputs(),
          outputs: outputs(),
          tx_data: any(),
          metadata: metadata()
        }

  @type outputs() :: list(Output.t()) | []
  @type metadata() :: <<_::256>> | nil

  @doc """
  Creates a new raw transaction structure from a list of inputs and a list of outputs, given in a succinct tuple form.

  assumptions:
  ```
    length(inputs) <= @max_inputs
    length(outputs) <= @max_outputs
  ```
  """
  @spec new(outputs(), outputs(), metadata()) :: t()
  def new(inputs, outputs, metadata) do
    %__MODULE__{tx_type: @tx_type, inputs: inputs, outputs: outputs, tx_data: @empty_tx_data, metadata: metadata}
  end

  @spec new(outputs(), outputs()) :: t()
  def new(inputs, outputs), do: new(inputs, outputs, @empty_metadata)

  @doc """
  Creates output for a payment v1 transaction
  """
  @spec new_output(Crypto.address_t(), Crypto.address_t(), pos_integer()) :: Output.t()
  def new_output(owner, token, amount) do
    %Output{
      output_type: @output_type,
      output_data: %{
        amount: :binary.encode_unsigned(amount),
        output_guard: owner,
        token: token
      }
    }
  end
end

defimpl ExPlasma.Transaction.Protocol, for: ExPlasma.Transaction.Type.PaymentV1 do
  alias ExPlasma.Output
  alias ExPlasma.Transaction.TypeMapper
  alias ExPlasma.Transaction.Type.PaymentV1
  alias ExPlasma.Utils.RlpDecoder

  @empty_metadata <<0::256>>
  @empty_tx_data 0
  @output_limit 4

  @tx_type TypeMapper.tx_type_for(:tx_payment_v1)
  @output_type TypeMapper.output_type_for(:output_payment_v1)

  @type validation_error() ::
          {:inputs, :duplicate_inputs}
          | {:inputs | :outputs, :cannot_exceed_maximum_value}
          | {:inputs | :outputs, :cannot_subceed_minimum_value}
          | {:output_type, :invalid_output_type_for_transaction}
          | {:tx_data, :malformed_tx_data}
          | {:metadata, :malformed_metadata}
          | {atom(), atom()}

  @type mapping_error() :: :malformed_transaction | :malformed_tx_data

  @doc """
  Turns a structure instance into a structure of RLP items, ready to be RLP encoded, for a raw transaction
  """
  @spec to_rlp(PaymentV1.t()) :: list(any())
  def to_rlp(%PaymentV1{} = transaction) do
    %PaymentV1{inputs: inputs, outputs: outputs, metadata: metadata} = transaction

    [
      <<@tx_type>>,
      Enum.map(inputs, &Output.to_rlp_id/1),
      Enum.map(outputs, &Output.to_rlp/1),
      @empty_tx_data,
      metadata || @empty_metadata
    ]
  end

  @doc """
  Decodes an RLP list into a Payment V1 Transaction.

  Only validates that the RLP is structurally correct.
  Does not perform any other kind of validation, use validate/1 for that.
  """
  @spec to_map(PaymentV1.t(), list()) :: {:ok, PaymentV1.t()} | {:error, mapping_error()}
  def to_map(%PaymentV1{}, [_tx_type, inputs_rlp, outputs_rlp, tx_data_rlp, metadata_rlp]) do
    with inputs <- Enum.map(inputs_rlp, &Output.decode_id/1),
         outputs <- Enum.map(outputs_rlp, &Output.decode/1),
         {:ok, tx_data} <- decode_tx_data(tx_data_rlp) do
      {:ok,
       %PaymentV1{
         tx_type: @tx_type,
         inputs: inputs,
         outputs: outputs,
         tx_data: tx_data,
         metadata: metadata_rlp
       }}
    end
  end

  def to_map(_), do: {:error, :malformed_transaction}

  defp decode_tx_data(tx_data_rlp) do
    case RlpDecoder.parse_uint256(tx_data_rlp) do
      {:ok, tx_data} -> {:ok, tx_data}
      _ -> {:error, :malformed_tx_data}
    end
  end

  @spec get_inputs(PaymentV1.t()) :: list(Output.t())
  def get_inputs(%PaymentV1{} = transaction), do: transaction.inputs

  @spec get_outputs(PaymentV1.t()) :: list(Output.t())
  def get_outputs(%PaymentV1{} = transaction), do: transaction.outputs

  @spec get_tx_type(PaymentV1.t()) :: pos_integer()
  def get_tx_type(%PaymentV1{} = transaction), do: transaction.tx_type

  @doc """
  Validates the Transaction.

  ## Example

  iex> txn = %{inputs: [%{output_data: [], output_id: %{blknum: 0, oindex: 0, position: 0, txindex: 0}, output_type: nil}], metadata: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>, outputs: [%{output_data: %{amount: <<0, 0, 0, 0, 0, 0, 0, 1>>, output_guard: <<29, 246, 47, 41, 27, 46, 150, 159, 176, 132, 157, 153, 217, 206, 65, 226, 241, 55, 0, 110>>, token: <<46, 38, 45, 41, 28, 46, 150, 159, 176, 132, 157, 153, 217, 206, 65, 226, 241, 55, 0, 110>>}, output_id: nil, output_type: 1}], sigs: [], tx_data: <<0>>, tx_type: <<1>>}
  iex> :ok = ExPlasma.Transaction.Type.PaymentV1.validate(txn)
  """
  @spec validate(PaymentV1.t()) :: :ok | {:error, validation_error()}
  def validate(%PaymentV1{} = transaction) do
    with :ok <- validate_inputs(transaction.inputs),
         :ok <- validate_outputs(transaction.outputs),
         :ok <- validate_tx_data(transaction.tx_data),
         :ok <- validate_metadata(transaction.metadata) do
      :ok
    end
  end

  defp validate_inputs(inputs) do
    with :ok <- validate_generic_output(inputs),
         :ok <- validate_unique_inputs(inputs),
         :ok <- validate_outputs_count(:inputs, inputs, 0) do
      :ok
    end
  end

  defp validate_outputs(outputs) do
    with :ok <- validate_generic_output(outputs),
         :ok <- validate_outputs_count(:outputs, outputs, 1),
         :ok <- validate_outputs_type(outputs) do
      :ok
    end
  end

  defp validate_generic_output([output | rest]) do
    with {:ok, _whatever} <- Output.validate(output), do: validate_generic_output(rest)
  end

  defp validate_generic_output([]), do: :ok

  defp validate_unique_inputs(inputs) do
    case inputs == Enum.uniq(inputs) do
      true -> :ok
      false -> {:error, {:inputs, :duplicate_inputs}}
    end
  end

  defp validate_outputs_count(field, list, _min_limit) when length(list) > @output_limit do
    {:error, {field, :cannot_exceed_maximum_value}}
  end

  defp validate_outputs_count(field, list, min_limit) when length(list) < min_limit do
    {:error, {field, :cannot_subceed_minimum_value}}
  end

  defp validate_outputs_count(_field, _list, _min_limit), do: :ok

  defp validate_outputs_type(outputs) do
    case Enum.all?(outputs, &(&1.output_type == @output_type)) do
      true -> :ok
      false -> {:error, {:output_type, :invalid_output_type_for_transaction}}
    end
  end

  # txData is required to be zero in the contract
  defp validate_tx_data(@empty_tx_data), do: :ok
  defp validate_tx_data(_), do: {:error, {:tx_data, :malformed_tx_data}}

  defp validate_metadata(metadata) when is_binary(metadata) and byte_size(metadata) == 32, do: :ok
  defp validate_metadata(_), do: {:error, {:metadata, :malformed_metadata}}
end