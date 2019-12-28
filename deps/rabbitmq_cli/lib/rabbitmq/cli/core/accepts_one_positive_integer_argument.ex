## The contents of this file are subject to the Mozilla Public License
## Version 1.1 (the "License"); you may not use this file except in
## compliance with the License. You may obtain a copy of the License
## at https://www.mozilla.org/MPL/
##
## Software distributed under the License is distributed on an "AS IS"
## basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
## the License for the specific language governing rights and
## limitations under the License.
##
## The Original Code is RabbitMQ.
##
## The Initial Developer of the Original Code is GoPivotal, Inc.
## Copyright (c) 2007-2020 Pivotal Software, Inc.  All rights reserved.

# Should be used by commands that require rabbit app to be stopped
# but need no other execution environment validators.
defmodule RabbitMQ.CLI.Core.AcceptsOnePositiveIntegerArgument do
  defmacro __using__(_) do
    quote do
      def validate(args, _) when length(args) == 0 do
        {:validation_failure, :not_enough_args}
      end

      def validate(args, _) when length(args) > 1 do
        {:validation_failure, :too_many_args}
      end

      def validate([value], _) when is_integer(value) do
        :ok
      end

      def validate([value], _) do
        case Integer.parse(value) do
          {n, _} when n >= 1 -> :ok
          :error -> {:validation_failure, {:bad_argument, "Argument must be a positive integer"}}
        end
      end

      def validate(_, _), do: :ok
    end
  end
end
