#####################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Update
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

    #Get previous account, select only $Account.Keys
    $SplatParams = @{
        Uri     = "$($Config.BaseUrl)/Users/$($PersonContext.References.Account)"
        Headers = $AuthorizationHeaders
        Method  = 'Get'
    }
    $OutputContext.PreviousData = Invoke-RestMethod @SplatParams | Select-Object $Account.PSObject.Properties.Name

    Write-Verbose -Verbose "Updating KPN Lisa account for '$($Person.DisplayName)'"

    $SplatParams = @{
        Uri     = "$($Config.BaseUrl)/Users/$($PersonContext.References.Account)/bulk"
        Headers = $AuthorizationHeaders
        Method  = 'Patch'
        Body    = $Account
    }

    if (-Not ($ActionContext.DryRun -eq $True)) {
        [void] (Invoke-RestMethod @SplatParams)
    }

    $AuditLogs.Add([PSCustomObject]@{
            Action  = "UpdateAccount" # Optionally specify a different action for this audit log
            Message = "Account for '$($Person.DisplayName)' Updated. ObjectId: '$($PersonContext.References.Account)'"
            IsError = $False
        })

    # Updating manager
    if ($Null -eq $PersonContext.References.ManagerAccount) {
        $splatDeleteManagerParams = @{
            Uri     = "$($Config.BaseUrl)/Users/$($PersonContext.References.Account)/manager"
            Method  = 'Delete'
            Headers = $AuthorizationHeaders
        }

        # TODO:: validate return value on update and delete for manager
        if (-Not ($ActionContext.DryRun -eq $True)) {
            [void] (Invoke-RestMethod @splatDeleteManagerParams)
        }

        $AuditLogs.Add([PSCustomObject]@{
                Action  = "UpdateAccount" # Optionally specify a different action for this audit log
                Message = "Manager for '$($Person.DisplayName)' deleted. ObjectId: '$($UserResponse.objectId)'"
                IsError = $False
            })
    }
    else {
        $splatUpdateManagerParams = @{
            Uri     = "$($Config.BaseUrl)/Users/$($PersonContext.References.Account)/Manager"
            Headers = $AuthorizationHeaders
            Method  = 'Put'
            Body    = $PersonContext.References.ManagerAccount
        }

        # TODO:: validate return value on update and delete for manager
        if (-Not ($ActionContext.DryRun -eq $True)) {
            [void] (Invoke-RestMethod @splatUpdateManagerParams)
        }

        $AuditLogs.Add([PSCustomObject]@{
                Action  = "UpdateAccount" # Optionally specify a different action for this audit log
                Message = "Manager for '$($Person.DisplayName)' Updated. ObjectId: '$($UserResponse.objectId)'"
                IsError = $False
            })
    }

    $OutputContext.Success = $True
}
catch {
    $Exception = $PSItem | Resolve-ErrorMessage

    Write-Verbose -Verbose $Exception.VerboseErrorMessage

    $AuditLogs.Add([PSCustomObject]@{
            Action  = "UpdateAccount" # Optionally specify a different action for this audit log
            Message = "Error updating account [$($Person.DisplayName) ($($PersonContext.References.Account))]. Error Message: $($Exception.ErrorMessage)."
            IsError = $True
        })
}
