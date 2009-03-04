module Sinatra
  module Hancock
    module OpenIDServer
      module Helpers
        def server
          if @server.nil?
            server_url = absolute_url('/sso')
            dir = File.join(Dir.tmpdir, 'openid-store')
            store = OpenID::Store::Filesystem.new(dir)
            @server = OpenID::Server::Server.new(store, server_url)
          end
          return @server
        end

        def yadis
          <<-ERB
<?xml version="1.0" encoding="UTF-8"?>
<xrds:XRDS
    xmlns:xrds="xri://$xrds"
    xmlns="xri://$xrd*($v*2.0)">
  <XRD>
    <Service priority="0">
      <% @types.each do |typ| %>
        <Type><%= typ %></Type>
      <% end %>
      <URI><%= absolute_url('/sso') %></URI>
    </Service>
  </XRD>
</xrds:XRDS>
ERB
        end

        def url_for_user
          absolute_url("/sso/users/#{session_user.id}")
        end

        def render_response(oidresp)
          if oidresp.needs_signing
            signed_response = server.signatory.sign(oidresp)
          end
          web_response = server.encode_response(oidresp)

          case web_response.code
          when 302
#            session.delete('OpenID::Consumer::last_requested_endpoint')
#            session.delete('OpenID::Consumer::DiscoveredServices::OpenID::Consumer::')
            session.delete(:return_to)
            redirect web_response.headers['location']
          else
            web_response.body
          end
        end
      end

      def self.registered(app)
        app.send(:include, Sinatra::Hancock::OpenIDServer::Helpers)

        app.get '/sso/xrds' do
          response.headers['Content-Type'] = 'application/xrds+xml'
          @types = [ OpenID::OPENID_IDP_2_0_TYPE ]
          erb yadis, :layout => false
        end

        app.get '/sso/users/:id' do
          @types = [ OpenID::OPENID_2_0_TYPE, OpenID::SREG_URI ]
          response.headers['Content-Type'] = 'application/xrds+xml'
          response.headers['X-XRDS-Location'] = absolute_url("/sso/users/#{params['id']}")

          erb yadis, :layout => false
        end

        [:get, :post].each do |meth|
          app.send(meth, '/sso') do
            begin
              oidreq = server.decode_request(params)
            rescue OpenID::Server::ProtocolError => e
              oidreq = session[:last_oidreq]
            end
            throw(:halt, [400, 'Bad Request']) unless oidreq

            oidresp = nil
            if oidreq.kind_of?(OpenID::Server::CheckIDRequest)
              session[:last_oidreq] = oidreq
              session[:return_to] = absolute_url('/sso')

              ensure_authenticated
              unless oidreq.identity == url_for_user
                forbidden!
              end
              forbidden! unless ::Hancock::Consumer.allowed?(oidreq.trust_root) 

              oidresp = oidreq.answer(true, nil, oidreq.identity)
              sreg_data = {
                'last_name'  => session_user.last_name,
                'first_name' => session_user.first_name,
                'email'      => session_user.email
              }
              sregresp = OpenID::SReg::Response.new(sreg_data)
              oidresp.add_extension(sregresp)
            else
              oidresp = server.handle_request(oidreq) #associate and more?
            end
            render_response(oidresp)
          end
        end
      end
    end
  end
  register Hancock::OpenIDServer
end
