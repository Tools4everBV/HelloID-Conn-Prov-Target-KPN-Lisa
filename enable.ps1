#####################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Enable
#
# Version: 1.0.0.0
#####################################################

#region functions
function Get-LisaAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]
        $TenantId,

        [Parameter(Mandatory)]
        [string]
        $ClientId,

        [Parameter(Mandatory)]
        [string]
        $ClientSecret,

        [Parameter(Mandatory)]
        [string]
        $Scope
    )

    try {
        $RestMethod = @{
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
        $Response = Invoke-RestMethod @RestMethod

        Write-Output $Response.access_token
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}


function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]
        $ErrorObject
    )

    process {
        $httpError = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }

        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpError.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpError.ErrorMessage = [System.IO.StreamReader]::new(
                $ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }

        Write-Output $httpError
    }
}


function Get-ErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]
        $ErrorObject
    )

    process {
        $ErrorMessage = [PSCustomObject]@{
            VerboseErrorMessage = $Null
            AuditErrorMessage   = $Null
        }

        if (
            $ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException' -or
            $ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException'
        ) {
            $HttpErrorObject = $ErrorObject | Resolve-HTTPError

            $ErrorMessage.VerboseErrorMessage = $HttpErrorObject.ErrorMessage
            $ErrorMessage.AuditErrorMessage = $HttpErrorObject.ErrorMessage
        }

        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($ErrorMessage.VerboseErrorMessage)) {
            $ErrorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message
        }
        if ([String]::IsNullOrEmpty($ErrorMessage.AuditErrorMessage)) {
            $ErrorMessage.AuditErrorMessage = $ErrorObject.Exception.Message
        }

        Write-Output $ErrorMessage
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
    Write-Verbose 'Getting accessToken'

    $SplatParams = @{
        TenantId     = $Config.TenantId
        ClientId     = $Config.ClientId
        ClientSecret = $Config.ClientSecret
        Scope        = $Config.Scope
    }
    $AccessToken = Get-LisaAccessToken @SplatParams

    $AuthorizationHeaders = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $AuthorizationHeaders.Add("Authorization", "Bearer $($AccessToken)")
    $AuthorizationHeaders.Add("Content-Type", "application/json")
    $AuthorizationHeaders.Add("Mwp-Api-Version", "1.0")

    Write-Verbose "Enable KPN Lisa account for '$($Person.DisplayName)'"

    $SplatParams = @{
        Uri     = "$($Config.BaseUrl)/Users/$($PersonContext.References.Account)"
        Headers = $AuthorizationHeaders
        Method  = 'Patch'
        Body    = @{
            propertyName = "accountEnabled"
            value        = $True
        }
    }

    if (-Not ($ActionContext.DryRun -eq $True)) {
        [void] (Invoke-RestMethod @SplatParams)
    }

    $AuditLogs.Add([PSCustomObject]@{
            Action  = "EnableAccount"
            Message = "Account for '$($Person.DisplayName)' is enabled"
            IsError = $False
        })

    $OutputContext.Success = $True
}
catch {
    $ex = $PSItem
    $ErrorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ErrorMessage.VerboseErrorMessage) [$($ex.ErrorDetails.Message)]"

    $AuditLogs.Add([PSCustomObject]@{
            Action  = "EnableAccount" # Optionally specify a different action for this audit log
            Message = "Error enabling account [$($Person.DisplayName) ($($PersonContext.References.Account))]. Error Message: $($ErrorMessage.AuditErrorMessage)."
            IsError = $True
        })
}
