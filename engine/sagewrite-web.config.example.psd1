@{
    # local: desktop/local use. cloud: server use.
    Mode = 'cloud'

    # Use 127.0.0.1 for local-only. Use 0.0.0.0 when a server must listen on the network.
    HostName = '0.0.0.0'
    Port = 3210

    # Parent folder that contains workspace-* directories.
    WorkspaceRoot = 'D:\SageWriteWorkspaces'

    # Use password mode before exposing the server beyond localhost.
    AuthMode = 'password'
    AdminPassword = 'change-this-password'

    # Optional. Leave empty to use the machine/user environment variable instead.
    OpenAIKey = ''

    # Useful for local desktop use. Usually false on a cloud/server machine.
    OpenBrowser = $false
}
