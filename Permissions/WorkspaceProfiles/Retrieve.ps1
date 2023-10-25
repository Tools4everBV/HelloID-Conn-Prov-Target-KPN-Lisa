#region functions
function Get-LisaAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]
        $TenantId,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]
        $ClientId,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]
        $ClientSecret,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]
        $Scope
    )

    try {
        $SplatParams = @{
            Uri         = "https://login.microsoftonline.com/$($TenantId)/oauth2/v2.0/token/"
            ContentType = "application/x-www-form-urlencoded"
            Method      = "Post"
            Body        = @{
                grant_type    = "client_credentials"
                client_id     = $ClientId
                client_secret = $ClientSecret
                scope         = $Scope
            }
        }
        $Response = Invoke-RestMethod @SplatParams

        Write-Output $Response.access_token
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}


function Get-LisaCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]
        $Uri,

        [Parameter(Mandatory)]
        [string]
        $Endpoint,

        [Parameter(Mandatory)]
        [string]
        $AccessToken
    )

    try {
        Write-Verbose 'Setting authorizationHeaders'

        $AuthorizationHeaders = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
        $AuthorizationHeaders.Add("Authorization", "Bearer $($AccessToken)")
        $AuthorizationHeaders.Add("Content-Type", "application/json")
        $AuthorizationHeaders.Add("Mwp-Api-Version", "1.0")

        $SplatParams = @{
            Uri     = "$($Uri)/$($Endpoint)"
            Method  = "Get"
            Headers = $AuthorizationHeaders
            Body    = @{
                Top       = 999
                SkipToken = $Null
            }
        }

        do {
            $Result = Invoke-RestMethod @SplatParams

            $SplatParams.Body.SkipToken = $Result.nextLink

            if ($Result -is [array]) {
                Write-Output $Result
            }
            else {
                Write-Output $Result.value
            }
        }
        until([string]::IsNullOrWhiteSpace($Result.nextLink))
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}


function Resolve-ErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]
        $ErrorObject
    )

    process {
        $Exception = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = $Null
            VerboseErrorMessage   = $Null
        }

        switch ($ErrorObject.Exception.GetType().FullName) {
            "Microsoft.PowerShell.Commands.HttpResponseException" {
                $Exception.ErrorMessage = $ErrorObject.ErrorDetails.Message
                break
            }
            "System.Net.WebException" {
                $Exception.ErrorMessage = [System.IO.StreamReader]::new(
                    $ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                break
            }
            default {
                $Exception.ErrorMessage = $ErrorObject.Exception.Message
            }
        }

        $Exception.VerboseErrorMessage = @(
            "Error at Line [$($ErrorObject.InvocationInfo.ScriptLineNumber)]: $($ErrorObject.InvocationInfo.Line)."
            "ErrorMessage: $($Exception.ErrorMessage) [$($ErrorObject.ErrorDetails.Message)]"
        ) -Join ' '

        Write-Output $Exception
    }
}
#endregion functions

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = @(
    [Net.SecurityProtocolType]::Tls
    [Net.SecurityProtocolType]::Tls11
    [Net.SecurityProtocolType]::Tls12
)

#region Aliasses
$Config = $ActionContext.Configuration
#endregion Aliasses

try {
    # Getting accessToken
    $AccessToken = $Config.AzureAD | Get-LisaAccessToken

    $SplatParams = @{
        Uri         = $Config.BaseUrl
        Endpoint    = "WorkspaceProfiles"
        AccessToken = $AccessToken
    }
    $WorkspaceProfiles = Get-LisaCollection @SplatParams

    $OutputContext.Permissions = $WorkspaceProfiles | ForEach-Object {
        [PSCustomObject]@{
            DisplayName    = "WorkspaceProfile - $($PSItem.friendlyDisplayName)"
            Identification = @{
                Reference = $PSItem.workspaceProfileId
            }
        }
    }
}
catch {
    $Exception = $PSItem | Resolve-ErrorMessage

    Write-Verbose -Verbose $Exception.VerboseErrorMessage

    throw $Exception.ErrorMessage
}
