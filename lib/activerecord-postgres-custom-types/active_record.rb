# Extends AR to add custom types functionality.
module ActiveRecord

	module ConnectionAdapters

		class PostgreSQLAdapter

			# Quotes the column value to help prevent {SQL injection attacks}
			def quote_with_custom_types(value, column = nil)
				if value.class < PostgresAbstractCustomType
					"'#{PostgreSQLColumn.custom_type_to_string(value, self).gsub(/'/, "''")}'"
				else
					quote_without_custom_types(value, column)
				end
			end

			alias_method_chain :quote, :custom_types

			class << self
				def register_custom_type_class(klass)
					self.custom_type_classes[klass.type] = klass
					TableDefinition.register_custom_type klass.type
					Table.register_custom_type klass.type
					register_arel_visitor klass
					register_oid_type klass
				end

				def register_arel_visitor(klass)
					Arel::Visitors::ToSql.class_eval <<-RUBY
						def visit_#{klass}(o, a=nil)
							@connection.quote(o) + '::#{klass.type}'
						end
					RUBY
				end

				def register_oid_type(klass)
					# only AR 4.X
				end

				# removes custom types definition (for testing)
				def unregister_custom_types(*custom_types)
					custom_types.each { |type| unregister_custom_type type }
				end

				# removes custom type definition (for testing)
				def unregister_custom_type(type)
					self.custom_type_classes.delete(type.to_sym)
					TableDefinition.unregister_custom_type type
					Table.unregister_custom_type type
				end

				def custom_type_classes
					@custom_type_classes ||= {}
				end
			end
		end

		class PostgreSQLColumn < Column
			# Adds custom type for the column.

			def custom_type_class
				PostgreSQLAdapter.custom_type_classes[type]
			end

			def klass_with_custom_types
				custom_type_klass = PostgreSQLAdapter.custom_type_classes[type]
				custom_type_klass || klass_without_custom_types
			end

			alias_method_chain :klass, :custom_types

			def self.string_to_custom_type(klass, string)
				return string unless String === string
				if string.present?
					klass.new(string)
				end
			end

			def self.string_to_custom_type(klass, string)
				return string unless String === string
				if string.present?
					fields = CompositeTypeParser.parse_data(string).map.with_index {|val, i| type_cast_custom_type_field(klass, i, val)}
					klass.new(fields)
				end
			end

			def self.type_cast_custom_type_field(klass, i, value)
				klass.initialize_column_definition

				column = klass.columns[i]
				raise "Invalid column index: #{i}" unless column
				cv = column.type_cast(value)
				if cv.is_a?(String)
					# unquote
					cv = cv.upcase == 'NULL' ? nil : cv.gsub(/\A"(.*)"\Z/m) { $1.gsub(/\\(.)/, '\1') }
				end
				cv
			end

			private

			def simplified_type_with_custom_types(field_type)
				type = field_type.to_sym
				if PostgreSQLAdapter.custom_type_classes.has_key?(type)
					type
				else
					simplified_type_without_custom_types(field_type)
				end
			end

			alias_method_chain :simplified_type, :custom_types
		end

		class << TableDefinition
			# Adds custom type for migrations. So you can add columns to a table like:
			#   create_table :people do |t|
			#     ...
			#     t.custom_type :custom_value
			#     ...
			#   end
			def register_custom_type(custom_type)
				class_eval <<-RUBY
					def #{custom_type}(*args)
						options = args.extract_options!
						column_names = args
						column_names.each { |name| column(name, '#{custom_type}', options) }
					end
				RUBY
			end

			# Removes custom types from migrations (for testing)
			def unregister_custom_type(custom_type)
				remove_method custom_type
			end
		end

		class << Table

			# Adds custom type for migrations. So you can add columns to a table like:
			#   change_table :people do |t|
			#     ...
			#     t.custom_type :custom_value
			#     ...
			#   end
			def register_custom_type(custom_type)
				class_eval <<-RUBY
					def #{custom_type}(*args)
						options = args.extract_options!
						column_names = args
						column_names.each { |name| column(name, '#{custom_type}', options) }
					end
				RUBY
			end

			# Removes custom types from migrations (for testing)
			def unregister_custom_type(custom_type)
				remove_method custom_type
			end

		end

	end

end

require_relative "active_record_#{ActiveRecord::VERSION::MAJOR}"