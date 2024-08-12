###################################################################
# HelloID-Conn-Prov-Target-KPNLisa-Update
# PowerShell V2
###################################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

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


# Hack for non updatable fields we like to return
# @link: https://helloid.canny.io/provisioning/p/exportdata-in-powershell-v2
$NonUpdatables = @(
    "userPrincipalName"
    "mail"
)


# Start Script
try {
    # Formatting Headers and authentication for KPN Lisa Requests
    $LisaRequest = @{
        Authentication = "Bearer"
        Token          = $actionContext.Configuration.AzureAD | Get-LisaAccessToken -AsSecureString
        ContentType    = "application/json; charset=utf-8"
        Headers        = @{
            "Mwp-Api-Version" = "1.0"
        }
    }

    #Get previous account, select only $outputContext.Data.Keys
    $SplatParams = @{
        Uri    = "$($actionContext.Configuration.BaseUrl)/Users/$($actionContext.References.Account)"
        Method = "Get"
    }
    $PreviousPerson = Invoke-RestMethod @LisaRequest @SplatParams

    $outputContext.PreviousData = $PreviousPerson | Select-Object -Property ([array] $outputContext.Data.PSObject.Properties.Name)

    Write-Verbose -Verbose "Updating KPN Lisa account for '$($personContext.Person.DisplayName)'"

    $SplatParams = @{
        Uri    = "$($actionContext.Configuration.BaseUrl)/Users/$($actionContext.References.Account)/bulk"
        Method = "Patch"
        Body   = $outputContext.Data | Select-Object -Property * -ExcludeProperty $NonUpdatables
    }

    if (-Not ($actionContext.DryRun -eq $True)) {
        [void] (Invoke-RestMethod @LisaRequest @SplatParams)
    }

    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = "UpdateAccount" # Optionally specify a different action for this audit log
            Message = "Account for '$($personContext.Person.DisplayName)' Updated. ObjectId: '$($actionContext.References.Account)'"
            IsError = $False
        })

    # Updating manager
    if ($Null -eq $actionContext.References.ManagerAccount) {
        $SplatParams = @{
            Uri    = "$($actionContext.Configuration.BaseUrl)/Users/$($actionContext.References.Account)/manager"
            Method = "Delete"
        }

        # TODO:: validate return value on update and delete for manager
        if (-Not ($actionContext.DryRun -eq $True)) {
            [void] (Invoke-RestMethod @LisaRequest @SplatParams)
        }

        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = "UpdateAccount" # Optionally specify a different action for this audit log
                Message = "Manager for '$($personContext.Person.DisplayName)' deleted. ObjectId: '$($UserResponse.objectId)'"
                IsError = $False
            })
    }
    else {
        $SplatParams = @{
            Uri    = "$($actionContext.Configuration.BaseUrl)/Users/$($actionContext.References.Account)/Manager"
            Method = "Put"
            Body   = $actionContext.References.ManagerAccount
        }

        # TODO:: validate return value on update and delete for manager
        if (-Not ($actionContext.DryRun -eq $True)) {
            [void] (Invoke-RestMethod @LisaRequest @SplatParams)
        }

        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = "UpdateAccount" # Optionally specify a different action for this audit log
                Message = "Manager for '$($personContext.Person.DisplayName)' Updated. ObjectId: '$($UserResponse.objectId)'"
                IsError = $False
            })
    }

    $outputContext.Success = $True
}
catch {
    $Exception = $PSItem | Resolve-ErrorMessage

    Write-Verbose -Verbose $Exception.VerboseErrorMessage

    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = "UpdateAccount" # Optionally specify a different action for this audit log
            Message = "Error updating account [$($personContext.Person.DisplayName) ($($actionContext.References.Account))]. Error Message: $($Exception.ErrorMessage)."
            IsError = $True
        })
}
