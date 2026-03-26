# frozen_string_literal: true

require 'sinatra'
require 'json'
require_relative 'MonitoringConfig'

set :port, 4567
set :bind, '0.0.0.0'
set :public_folder, File.join(Dir.pwd, 'public')

before do
  content_type :json
end

def load_config
  MonitoringConfig.new
end

$config = load_config

get '/api/entries' do
  q = params[:q]&.downcase || ''
  entries = $config.entries.select do |e|
    e.description.downcase.include?(q)
  end

  entries.map do |e|
    {
      id: e.id,
      description: e.description,
      email: e.email,
      source: e.source,
      sla: e.sla,
      monitor_endpoints: e.monitor_endpoints,
      monitor_connectivity: e.monitor_connectivity,
      monitor_backup: e.monitor_backup,
      monitor_dtc: e.monitor_dtc,
      create_ticket: e.create_ticket
    }
  end.to_json
end

put '/api/entries/:id' do
  id = params[:id]
  data = JSON.parse(request.body.read)

  entry = $config.by_id(id)
  if entry
    entry.description = data['description'] if data['description']
    entry.email = data['email'] if data['email']
    entry.sla = data['sla'] || []
    entry.monitor_endpoints = data['monitor_endpoints']
    entry.monitor_connectivity = data['monitor_connectivity']
    entry.monitor_backup = data['monitor_backup']
    entry.monitor_dtc = data['monitor_dtc']
    entry.create_ticket = data['create_ticket']
    entry.touch

    { success: true }.to_json
  else
    status 404
    { error: 'Entry not found' }.to_json
  end
end

post '/api/save' do
  $config.save_config
  { success: true }.to_json
end

get '/' do
  send_file File.join(settings.public_folder, 'index.html')
end
