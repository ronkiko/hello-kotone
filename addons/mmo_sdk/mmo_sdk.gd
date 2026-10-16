extends Node
## SDK factory. Add this node to your tree; it owns the clients it creates.
## No connection, network request or autoload is started by creating the addon.
const Client = preload("client.gd")

func create_client() -> Client:
    if not is_inside_tree() or is_queued_for_deletion():
        return null
    var client := Client.new()
    add_child(client)
    return client
