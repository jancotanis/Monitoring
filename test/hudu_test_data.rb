# frozen_string_literal: true

require 'json'
require 'wrapi'

LAYOUT_TEST_STRING = <<~JSON
{
    "id": 22,
    "slug": "company-service-5a37d919649a",
    "name": "Company Dashboard",
    "icon": "fas fa-circle",
    "color": "#5b17f2",
    "icon_color": "#FFFFFF",
    "sidebar_folder_id": 15,
    "active": true,
    "include_passwords": true,
    "include_photos": true,
    "include_comments": true,
    "include_files": true,
    "created_at": "2023-10-24T11:04:11.772Z",
    "updated_at": "2023-11-06T15:46:52.570Z",
    "location": null,
    "fields": [
        {
            "id": 401,
            "label": "Exclaimer:ENABLED",
            "show_in_list": false,
            "field_type": "CheckBox",
            "required": null,
            "hint": "",
            "min": null,
            "max": null,
            "linkable_id": 41,
            "expiration": false,
            "options": "",
            "multiple_options": null,
            "list_id": null,
            "column_width": "variable",
            "position": 10,
            "is_destroyed": false
        },
        {
            "id": 201,
            "label": "Cloudally Office365 Backup:ENABLED",
            "show_in_list": false,
            "field_type": "CheckBox",
            "required": null,
            "hint": "",
            "min": null,
            "max": null,
            "linkable_id": 5,
            "expiration": false,
            "options": "",
            "multiple_options": null,
            "list_id": null,
            "column_width": "variable",
            "position": 1,
            "is_destroyed": false
        },
        {
            "id": 202,
            "label": "Cloudally Office365 Backup:NOTE",
            "show_in_list": false,
            "field_type": "Text",
            "required": null,
            "hint": "",
            "min": null,
            "max": null,
            "linkable_id": 5,
            "expiration": false,
            "options": "",
            "multiple_options": null,
            "list_id": null,
            "column_width": "variable",
            "position": 2,
            "is_destroyed": false
        },
        {
            "id": 413,
            "label": "Cloudally Office365 Backup:URL",
            "show_in_list": false,
            "field_type": "Text",
            "required": null,
            "hint": "",
            "min": null,
            "max": null,
            "linkable_id": 41,
            "expiration": false,
            "options": "",
            "multiple_options": null,
            "list_id": null,
            "column_width": "variable",
            "position": 3,
            "is_destroyed": false
        }
    ]
}
JSON
ASSET_TEST_STRING = <<~JSON
{
    "id": 22,
    "slug": "company-service-5a37d919649a",
    "name": "Company Dashboard",
    "icon": "fas fa-circle",
    "color": "#5b17f2",
    "icon_color": "#FFFFFF",
    "sidebar_folder_id": 15,
    "active": true,
    "include_passwords": true,
    "include_photos": true,
    "include_comments": true,
    "include_files": true,
    "created_at": "2023-10-24T11:04:11.772Z",
    "updated_at": "2023-11-06T15:46:52.570Z",
    "location": null,
    "fields": [
        {
            "id": 201,
            "label": "Cloudally Office365 Backup:ENABLED",
            "show_in_list": false,
            "field_type": "CheckBox",
            "required": null,
            "hint": "",
            "min": null,
            "max": null,
            "linkable_id": 5,
            "expiration": false,
            "options": "",
            "multiple_options": null,
            "list_id": null,
            "column_width": "variable",
            "position": 1,
            "is_destroyed": false,
            "value": "Cloudally Office365 Backup:ENABLED"
        },
        {
            "id": 202,
            "label": "Cloudally Office365 Backup:NOTE",
            "show_in_list": false,
            "field_type": "Text",
            "required": null,
            "hint": "",
            "min": null,
            "max": null,
            "linkable_id": 5,
            "expiration": false,
            "options": "",
            "multiple_options": null,
            "list_id": null,
            "column_width": "variable",
            "position": 2,
            "is_destroyed": false,
            "value": "Cloudally Office365 Backup:NOTE"
        },
        {
            "id": 413,
            "label": "Cloudally Office365 Backup:URL",
            "show_in_list": false,
            "field_type": "Text",
            "required": null,
            "hint": "",
            "min": null,
            "max": null,
            "linkable_id": 41,
            "expiration": false,
            "options": "",
            "multiple_options": null,
            "list_id": null,
            "column_width": "variable",
            "position": 3,
            "is_destroyed": false,
            "value": "Cloudally Office365 Backup:URL"
        }
    ]
}
JSON

LAYOUT_TEST_JSON = WrAPI::Request::Entity.create(JSON.parse(LAYOUT_TEST_STRING))
ASSET_TEST_JSON = WrAPI::Request::Entity.create(JSON.parse(ASSET_TEST_STRING))
