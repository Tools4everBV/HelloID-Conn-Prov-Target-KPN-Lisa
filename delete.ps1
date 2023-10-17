#####################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Delete
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
        $errorMessage = [PSCustomObject]@{
            VerboseErrorMessage = $null
            AuditErrorMessage   = $null
        }

        if (
            $ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException' -or
            $ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException'
        ) {
            $httpErrorObject = Resolve-HTTPError -Error $ErrorObject

            $errorMessage.VerboseErrorMessage = $httpErrorObject.ErrorMessage
            $errorMessage.AuditErrorMessage = $httpErrorObject.ErrorMessage
        }

        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($errorMessage.VerboseErrorMessage)) {
            $errorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message
        }
        if ([String]::IsNullOrEmpty($errorMessage.AuditErrorMessage)) {
            $errorMessage.AuditErrorMessage = $ErrorObject.Exception.Message
        }

        Write-Output $errorMessage
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
$Config = $actionContext.Configuration
$Account = $outputContext.Data
$AuditLogs = $outputContext.AuditLogs

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
    $accessToken = Get-LisaAccessToken @SplatParams

    $authorizationHeaders = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $authorizationHeaders.Add("Authorization", "Bearer $($accessToken)")
    $authorizationHeaders.Add("Content-Type", "application/json")
    $authorizationHeaders.Add("Mwp-Api-Version", "1.0")

    Write-Verbose "Removing KPN Lisa account for '$($Person.DisplayName)'"

    $SplatParams = @{
        Uri     = "$($Config.BaseUrl)/Users/$($personContext.References.Account)"
        Headers = $authorizationHeaders
        Method  = 'Delete'
    }

    if (-Not($actionContext.DryRun -eq $True)) {
        [void] (Invoke-RestMethod @SplatParams)
    }

    $AuditLogs.Add([PSCustomObject]@{
            Action  = "DeleteAccount" # Optionally specify a different action for this audit log
            Message = "Account for '$($Person.DisplayName)' is deleted"
            IsError = $False
        })

    $outputContext.Success = $True
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage) [$($ex.ErrorDetails.Message)]"

    $auditLogs.Add([PSCustomObject]@{
            Action  = "DeleteAccount" # Optionally specify a different action for this audit log
            Message = "Error deleting account [$($Person.DisplayName) ($($personContext.References.Account))]. Error Message: $($errorMessage.AuditErrorMessage)."
            IsError = $True
        })
}
