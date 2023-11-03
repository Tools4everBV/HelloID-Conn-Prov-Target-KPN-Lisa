#####################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Delete
#
# Version: 1.0.0.0
#####################################################

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
$Account = $OutputContext.Data
$AuditLogs = $OutputContext.AuditLogs

$Person = $PersonContext.Person
$Manager = $PersonContext.Manager
#endregion Aliasses

# Start Script
try {
    # Getting accessToken
    $AccessToken = $Config.AzureAD | Get-LisaAccessToken

    # Formatting Authorisation Headers
    $AuthorizationHeaders = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $AuthorizationHeaders.Add("Authorization", "Bearer $($AccessToken)")
    $AuthorizationHeaders.Add("Content-Type", "application/json")
    $AuthorizationHeaders.Add("Mwp-Api-Version", "1.0")

    Write-Verbose -Verbose "Removing KPN Lisa account for '$($Person.DisplayName)'"

    $SplatParams = @{
        Uri     = "$($Config.BaseUrl)/Users/$($PersonContext.References.Account)"
        Headers = $AuthorizationHeaders
        Method  = 'Delete'
    }

    try {
        if (-not($ActionContext.DryRun -eq $true)) {
            [void] (Invoke-RestMethod @splatParams)
        }

        $AuditLogs.Add([PSCustomObject]@{
                Action  = "DeleteAccount" # Optionally specify a different action for this audit log
                Message = "Account for '$($p.DisplayName)' is deleted"
                IsError = $False
            })
    }
    catch {
        $StatusCode = $_.Exception.Response.StatusCode

        if ($StatusCode -eq [System.Net.HttpStatusCode]::NotFound) {
            $AuditLogs.Add([PSCustomObject]@{
                    Action  = "DeleteAccount" # Optionally specify a different action for this audit log
                    Message = "Account for '$($p.DisplayName)' doesn't exist, mark as deleted"
                    IsError = $False
                })
        }
        else {
            throw $_
        }
    }

    $OutputContext.Success = $True
}
catch {
    $Exception = $PSItem | Resolve-ErrorMessage

    Write-Verbose -Verbose $Exception.VerboseErrorMessage

    $AuditLogs.Add([PSCustomObject]@{
            Action  = "DeleteAccount" # Optionally specify a different action for this audit log
            Message = "Error deleting account [$($Person.DisplayName) ($($PersonContext.References.Account))]. Error Message: $($Exception.ErrorMessage)."
            IsError = $True
        })
}
