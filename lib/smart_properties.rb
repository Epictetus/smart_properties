module SmartProperties
  
  VERSION = "0.0.1"
  
  class Property

    attr_reader :name
    attr_reader :default
    attr_reader :converter
    attr_reader :validator
    attr_reader :scope

    def initialize(name, attrs = {})
      @name      = name.to_sym
      @default   = attrs[:default]
      @converter = attrs[:converts]
      @validator = attrs[:accepts]
      @required  = !!attrs[:required]
    end

    def required=(value)
      @required = !!value
    end

    def required?
      @required
    end

    def convert(value, scope)
      return value unless converter

      if converter.respond_to?(:call)
        scope.instance_exec(value, &converter)
      else
        begin
          value.send(:"#{converter}")
        rescue NoMethodError
          raise ArgumentError, "#{value.class.name} does not respond to ##{converter}"
        end
      end
    end

    def valid?(value, scope)
      return true unless value
      return true unless validator

      if validator.respond_to?(:call)
        !!scope.instance_exec(value, &validator)
      elsif validator.kind_of?(Enumerable)
        validator.include?(value)
      else
        validator === value
      end
    end
    
    def prepare(value, scope)
      if required? && value.nil?
        raise ArgumentError, "#{scope.class.name} requires the property #{self.name} to be set"
      end

      value = convert(value, scope) unless value.nil?

      unless valid?(value, scope)
        raise ArgumentError, "#{scope.class.name} does not accept #{value.inspect} as value for the property #{self.name}"
      end

      @value = value
    end
    
    def define(scope)
      property = self

      scope.send(:attr_reader, name)
      scope.send(:define_method, :"#{name}=") do |value|
        instance_variable_set("@#{property.name}", property.prepare(value, self))
      end
    end

  end
  
  module ClassMethods

    ##
    # Returns the list of properties for a widget. This includes the
    # properties than have been defined in the parent classes.
    #
    # @return [Array<Property>] The list of properties for this widget.
    #
    def properties
      (@properties || {}).dup
    end

    ##
    # Defines a new property from a name and a set of options. This basically
    # results in creating a getter and setter pair that provides some
    # additional features:
    #
    # 1. Validation of input data by specifiying the +:accepts+ option:
    #    If you use a class as value for this option, the setter will check
    #    if the value it is about to assign is of this type. If you use an
    #    array, the setter will check if the value it is about to assign is
    #    included in this array. Finally, if you specify a block, it will
    #    invoke the block with the value it is about to assign and check if
    #    the block returns a thruthy value, meaning anything but +false+ and
    #    +nil+.
    #
    # 2. Conversion of input data by specifiying the +:converts+ option:
    #    If you use provide a symbol as value for this option, the setter will
    #    invoke this method on the object it is about to assign and take the
    #    result of this call instead. If you provide a block, it will invoke
    #    the block with the value it is about to assign and take the result
    #    of the block instead.
    #
    # 3. Providing a default value by specifiying an +:default+ option.
    #
    # 4. Forcing a property to be present by setting the +:required+ option
    #    to true.
    #
    #
    # @param [Symbol] name the name of the property
    #
    # @param [Hash] options the list of options used to configure the property
    # @option options [Array, Class, Proc] :accepted
    #   specifies how the validation is done
    # @option options [Proc, Symbol] :convert
    #   specifies how the conversion is done
    # @option options :default
    #   specifies the default value of the property
    # @option options [true, false] :required
    #   specifies whether or not this property is required
    #
    # @return [Property] The defined property.
    #
    # @example Definition of a property that is mandatory, converts the provided input to a symbol, checks that the symbol is either +:de+ or +:en+, and defaults to +:de+.
    #
    #  property :language_code, :accepts => [:de, :en],
    #                           :converts => :to_sym,
    #                           :default  => :de,
    #                           :required => true
    #
    def property(name, options = {})
      @properties ||= begin        
        parent = if self != SmartProperties
          (ancestors[1..-1].find { |klass| klass.ancestors.include?(SmartProperties) && klass != SmartProperties })
        end
        
        parent ? parent.properties : {}
      end
      
      p = Property.new(name, options)
      p.define(self)
      
      @properties[name] = p
    end

  end
  
  ##
  # Extends the class, which this module is included in, with a property 
  # method to define properties.
  #
  # @param [Class] base the class this module is included in
  #
  def self.included(base)
    base.extend(ClassMethods)
  end
  
  ##
  # Reads a property's value. Use this method if you override the
  # automatically generated getter and want to access it.
  #
  def read_property(name)
    if property = self.class.properties[name]
      property.get
    else
      raise ArgumentError, "#{self.class} does not have a property called #{name}"
    end
  end
  
  ##
  # Sets a property's value. Use this method if you override the
  # automatically generated setter and want to access it.
  #
  # @param value the property's new value
  #
  def write_property(name, value)
    if property = self.class.properties[name]
      property.set(value)
    else
      raise ArgumentError, "#{self.class} does not have a property called #{name}"
    end
  end
  
  ##
  # Creates a new widget from the provided attributes.
  #
  # @param [Hash] attrs the set of attributes that holds the values for the
  #   various properties of this widget
  #
  def initialize(attrs = {})
    attrs ||= {}

    self.class.properties.each do |_, property|
      value = attrs.key?(property.name) ? attrs.delete(property.name) : property.default
      send(:"#{property.name}=", value)
    end
  end

end
