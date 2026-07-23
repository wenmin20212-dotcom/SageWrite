@{
    # local: desktop/local use. cloud: server use.
    Mode = 'cloud'

    # Use 127.0.0.1 for local-only. Use 0.0.0.0 when a server must listen on the network.
    HostName = '0.0.0.0'
    Port = 3210

    # Parent folder that contains workspace-* directories.
    WorkspaceRoot = 'D:\SageWriteWorkspaces'

    # Use users mode before exposing the server beyond localhost.
    # On first start, AdminUser/AdminPassword create the first admin in UsersFile.
    AuthMode = 'users'
    AdminUser = 'admin'
    AdminPassword = 'change-this-password'

    # Optional. Leave empty to use engine\data\users.json.
    UsersFile = ''

    # Optional. Leave empty to use <WorkspaceRoot>\users\<user-id>.
    UserWorkspaceRoot = ''

    # Optional. Leave empty to use the machine/user environment variable instead.
    OpenAIKey = ''

    # Useful for local desktop use. Usually false on a cloud/server machine.
    OpenBrowser = $false
}
