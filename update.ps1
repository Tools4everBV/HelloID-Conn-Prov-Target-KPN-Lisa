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
        $Scope,

        [Parameter()]
        [switch]
        $AsSecureString
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

        if ($AsSecureString) {
            Write-Output ($Response.access_token | ConvertTo-SecureString -AsPlainText)
        }
        else {
            Write-Output ($Response.access_token)
        }
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
        ) -Join " "

        Write-Output $Exception
    }
}
#endregion functions


#region Aliasses
$Config = $ActionContext.Configuration
$Account = $OutputContext.Data
$AuditLogs = $OutputContext.AuditLogs

$Person = $PersonContext.Person
$Manager = $PersonContext.Manager
#endregion Aliasses


# Start Script
try {
    # Formatting Headers and authentication for KPN Lisa Requests
    $LisaRequest = @{
        Authentication = "Bearer"
        Token          = $Config.AzureAD | Get-LisaAccessToken -AsSecureString
        ContentType    = "application/json; charset=utf-8"
        Headers        = @{
            "Mwp-Api-Version" = "1.0"
        }
    }

    #Get previous account, select only $Account.Keys
    $SplatParams = @{
        Uri    = "$($Config.BaseUrl)/Users/$($PersonContext.References.Account)"
        Method = "Get"
    }
    $PreviousPerson = Invoke-RestMethod @LisaRequest @SplatParams

    $OutputContext.PreviousData = $PreviousPerson | Select-Object $Account.PSObject.Properties.Name

    Write-Verbose -Verbose "Updating KPN Lisa account for '$($Person.DisplayName)'"

    $SplatParams = @{
        Uri    = "$($Config.BaseUrl)/Users/$($PersonContext.References.Account)/bulk"
        Method = "Patch"
        Body   = $Account
    }

    if (-Not ($ActionContext.DryRun -eq $True)) {
        [void] (Invoke-RestMethod @LisaRequest @SplatParams)
    }

    $AuditLogs.Add([PSCustomObject]@{
            Action  = "UpdateAccount" # Optionally specify a different action for this audit log
            Message = "Account for '$($Person.DisplayName)' Updated. ObjectId: '$($PersonContext.References.Account)'"
            IsError = $False
        })

    # Updating manager
    if ($Null -eq $PersonContext.References.ManagerAccount) {
        $SplatParams = @{
            Uri    = "$($Config.BaseUrl)/Users/$($PersonContext.References.Account)/manager"
            Method = "Delete"
        }

        # TODO:: validate return value on update and delete for manager
        if (-Not ($ActionContext.DryRun -eq $True)) {
            [void] (Invoke-RestMethod @LisaRequest @SplatParams)
        }

        $AuditLogs.Add([PSCustomObject]@{
                Action  = "UpdateAccount" # Optionally specify a different action for this audit log
                Message = "Manager for '$($Person.DisplayName)' deleted. ObjectId: '$($UserResponse.objectId)'"
                IsError = $False
            })
    }
    else {
        $SplatParams = @{
            Uri    = "$($Config.BaseUrl)/Users/$($PersonContext.References.Account)/Manager"
            Method = "Put"
            Body   = $PersonContext.References.ManagerAccount
        }

        # TODO:: validate return value on update and delete for manager
        if (-Not ($ActionContext.DryRun -eq $True)) {
            [void] (Invoke-RestMethod @LisaRequest @SplatParams)
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
