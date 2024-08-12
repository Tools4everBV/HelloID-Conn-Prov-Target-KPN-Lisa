###################################################################
# HelloID-Conn-Prov-Target-KPNLisa-WorkspaceProfiles-Revoke
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

    $SplatParams = @{
        Uri    = "$($actionContext.Configuration.BaseUrl)/Users/$($actionContext.References.Account)/workspaceprofiles"
        Method = "Delete"
    }

    if (-Not ($actionContext.DryRun -eq $True)) {
        [void] (Invoke-RestMethod @LisaRequest @SplatParams) #If 200 it returns a Empty String
    }

    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = "RevokePermission"
            Message = "LicenseProfile Permission $($actionContext.References.Permission.Reference) removed from account [$($personContext.Person.DisplayName) ($($actionContext.References.Account))]"
            IsError = $False
        })

    $outputContext.Success = $True
}
catch {
    $Exception = $PSItem | Resolve-ErrorMessage

    Write-Verbose -Verbose $Exception.VerboseErrorMessage

    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = "RevokePermission" # Optionally specify a different action for this audit log
            Message = "Failed to remove LicenseProfile permission $($actionContext.References.Permission.Reference) from account [$($personContext.Person.DisplayName) ($($actionContext.References.Account))]. Error Message: $($Exception.ErrorMessage)."
            IsError = $True
        })
}
