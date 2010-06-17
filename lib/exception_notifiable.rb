require 'ipaddr'

# Copyright (c) 2005 Jamis Buck
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
module ExceptionNotifiable
  def self.included(target)
    target.extend(ClassMethods)
  end

  module ClassMethods
    def consider_local(*args)
      local_addresses.concat(args.flatten.map { |a| IPAddr.new(a) })
    end

    def local_addresses
      addresses = read_inheritable_attribute(:local_addresses)
      unless addresses
        addresses = [IPAddr.new("127.0.0.1")]
        write_inheritable_attribute(:local_addresses, addresses)
      end
      addresses
    end

    # Pass a symbol to specify a method in your controller (likely ApplicationController) that will return a hash of additional data to be available to the ExceptionNotifier views
    # Pass a proc if you have a proc that will return the extra data.
    # I'm not sure what happens if you pass self?
    def exception_data(deliverer=self)
      if deliverer == self
        read_inheritable_attribute(:exception_data)
      else
        write_inheritable_attribute(:exception_data, deliverer)
      end
    end

    def exceptions_to_treat_as_404
      exceptions = [ActiveRecord::RecordNotFound,
                    ActionController::UnknownController,
                    ActionController::UnknownAction]
      exceptions << ActionController::RoutingError if ActionController.const_defined?(:RoutingError)
      exceptions
    end
  end

  public

    # You can send a notice manually, even without an exception notice. Just pass a hash with these keys:
    # * error_class (optional)
    # * message
    def notify_of(hash_or_exception)
      notice = normalize_notice(hash_or_exception)

      source_of_extra_data = self.class.exception_data
      extra_data = case source_of_extra_data
        when nil then {}
        when Symbol then send(source_of_extra_data)
        when Proc then source_of_extra_data.call(self)
      end
      notice.merge!(extra_data)

      ExceptionNotifier.deliver_exception_notification(notice)
    end

  private

    def local_request?
      #Rails.logger.debug "ExceptionNotifiable: local_request?"
      remote = IPAddr.new(request.remote_ip)
      !self.class.local_addresses.detect { |addr| addr.include?(remote) }.nil?
    end


    def render_404
      respond_to do |type|
        type.html { render :file => "#{RAILS_ROOT}/public/404.html", :status => "404 Not Found" }
        type.all  { render :nothing => true, :status => "404 Not Found" }
      end
    end

    def render_500
      respond_to do |type|
        type.html { render :file => "#{RAILS_ROOT}/public/500.html", :status => "500 Error" }
        type.all  { render :nothing => true, :status => "500 Error" }
      end
    end

    def normalize_notice(notice) #:nodoc:
      data = {
        :environment => ENV.to_hash,
      }

      if self.respond_to?(:controller_name) && self.respond_to?(:action_name)
        data[:location] = "#{controller_name}##{action_name}"
        data[:controller] =self
      end

      if self.respond_to? :request
        data.merge!({
          :request        => request,
          :remote_address => (request.env["HTTP_X_FORWARDED_HOST"] || request.env["HTTP_HOST"]),
          :rails_root     => rails_root,
          :params         => request.parameters.to_hash,
          :url            => "#{request.protocol}#{request.host}#{request.request_uri}",
        })
        data[:environment].merge!(request.env.to_hash)
      end

      if self.respond_to? :session
        data.merge!({
          :session      => session,
          :session_id   => session.instance_variable_get("@session_id"),
          :session_data => session.respond_to?(:to_hash) ?
                           session.to_hash :
                           session.instance_variable_get("@data")
        })
      end

      case notice
      when Hash
        data.merge!({
          :location    => sanitize_backtrace(caller)[1],
          :backtrace   => sanitize_backtrace(caller),
          :error_class => notice[:message],
        })
        data.merge!(notice)
      when Exception
        data.merge!(exception_to_data(notice))
      end
      data
    end

    def exception_to_data(exception)
      data = {
        :exception     => exception,
        :error_class   => exception.class.name,
        :message       => exception.message,
        :backtrace     => sanitize_backtrace(exception.backtrace),
      }
      data
    end

    def rescue_action_in_public(exception)
      case exception
        when *self.class.exceptions_to_treat_as_404
          render_404

        else
          render_500
          notify_of exception
      end
    end

    def sanitize_backtrace(trace)
      re = Regexp.new(/^#{Regexp.escape(rails_root)}\//)
      trace.map { |line| Pathname.new(line.gsub(re, "")).cleanpath.to_s }
    end

    def rails_root
      @rails_root ||= Pathname.new(RAILS_ROOT).cleanpath.to_s
    end


  # Since we can't instantiate ExceptionNotifiable directly (since it's a module), we need a class to put the ExceptionNotifiable methods to allow users to send notifications manually outside of a controller (normally the controller class is the class we use).
  class FakeController
#    def rescue_action_in_public(exception)
#    end

    include ExceptionNotifiable
  end
end
