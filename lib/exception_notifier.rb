require 'pathname'

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
class ExceptionNotifier < ActionMailer::Base
  @@sender_address = %("Exception Notifier" <exception.notifier@default.com>)
  cattr_accessor :sender_address

  @@exception_recipients = []
  cattr_accessor :exception_recipients

  @@email_prefix = "[ERROR] "
  cattr_accessor :email_prefix

  @@sections = %w(request session environment backtrace)
  cattr_accessor :sections

  self.template_root = "#{File.dirname(__FILE__)}/../views"

  def self.reloadable?() false end

  def exception_notification(notice={})
    content_type "text/plain"

    subject    "#{email_prefix}in #{notice[:location]}: #{notice[:error_class]}: #{notice[:message]}"

    recipients exception_recipients
    from       sender_address

    body       notice.merge({
                  :sections => sections 
               })
  end

  def self.notify_of(*args)
    ExceptionNotifiable::FakeController.new.notify_of(*args)
  end

end
