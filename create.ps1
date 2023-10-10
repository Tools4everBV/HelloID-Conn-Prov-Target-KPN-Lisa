#####################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Create
#
# Version: 1.0.0.0
#####################################################

#region Config
$Config = $Configuration | ConvertFrom-Json
#endregion Config

#region default properties
$p = $Person | ConvertFrom-Json
$m = $Manager | ConvertFrom-Json

$aRef = $null # New-Guid
$mRef = $managerAccountReference | ConvertFrom-Json

$AuditLogs = [Collections.Generic.List[PSCustomObject]]::new()
#endregion default properties

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = @(
    [Net.SecurityProtocolType]::Tls
    [Net.SecurityProtocolType]::Tls11
    [Net.SecurityProtocolType]::Tls12
)

#region functions
#Primary Email and UPN Generation
# 1. <First Name>.<Last name prefix><Last Name>@<Domain> (e.g janine.vandenboele@yourdomain.com)
# 2. <First Name (initial)>.<last name prefix><Last Name>@<Domain> (e.g j.vandenboele@yourdomain.com)
# 3. <First Name (2 initials)>.<Last name prefix><Last Name><iterator> @<Domain>(e.g ja.vandenboele@yourdomain.com)
# 4. <First Name>.<Last name prefix><Last Name><iterator> @<Domain>(e.g janine.vandenboele2@yourdomain.com)
function New-UserPrincipalName {
    [cmdletbinding()]
    Param (
        [Parameter(Mandatory)]
        [object]
        $person,

        [Parameter(Mandatory)]
        [string]
        $domain,

        [Parameter(Mandatory)]
        [int]
        $Iteration
    )

    Process {
        try {
            $suffix = "";

            #Check Nickname
            if ([string]::IsNullOrEmpty($person.Name.Nickname)) {
                $tempFirstName = $person.Name.GivenName
            }
            else {
                $tempFirstName = $person.Name.Nickname
            }

            $tempFirstName = $tempFirstName -Replace ' ', ''


            switch ($Iteration) {
                0 {
                    $tempFirstName = $tempFirstName
                    Break
                }
                1 {
                    $tempFirstName = $tempFirstName.substring(0, 1)
                    Break
                }
                2 {
                    $tempFirstName = $tempFirstName.substring(0, 2)
                    Break
                }
                default {
                    $tempFirstName = $tempFirstName
                    $suffix = "$($Iteration-1)"
                }
            }

            if ($personObj.PrimaryContract.custom.suffix -eq 'impegno.nl') {
                if ([string]::IsNullOrEmpty($person.Name.Nickname)) { $tempFirstName = $person.Name.GivenName } else { $tempFirstName = $person.Name.Nickname }
                $tempFirstName = $tempFirstName -Replace ' ', ''
                switch ($Iteration) {
                    0 {
                        $tempFirstName = $tempFirstName.substring(0, 1)
                        Break
                    }
                    1 {
                        $tempFirstName = $tempFirstName
                        Break
                    }
                    2 {
                        $tempFirstName = $tempFirstName.substring(0, 2)
                        Break
                    }
                    default {
                        $tempFirstName = $tempFirstName
                        $suffix = "$($Iteration-1)"
                    }
                }
            }

            #if([string]::IsNullOrEmpty($p.Name.FamilyNamePrefix)) { $tempLastNamePrefix = "" } else { $tempLastNamePrefix = $p.Name.FamilyNamePrefix -replace ' ','' }
            $tempLastName = $person.Custom.KpnLisaUpnMailLastname
            $tempUsername = $tempFirstName + "." + $tempLastName
            $tempUsername = $tempUsername.substring(0, [Math]::Min(64 - $suffix.Length, $tempUsername.Length))  #max 64 chars for email address and upn
            $result = ("{0}{1}@{2}" -f $tempUsername, $suffix, $domain)
            $result = $result.toLower()
            $result = $result.replace("'", "")
            $result = [Text.Encoding]::ASCII.GetString([Text.Encoding]::GetEncoding("Cyrillic").GetBytes($result))
            return $result
        }
        catch {
            throw("An error was found in the name convention algorithm: $($_.Exception.Message): $($_.ScriptStackTrace)")
        }
    }
}


function Get-SurName {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $person
    )

    process {
        $FamilyName = "$($person.name.FamilyNamePrefix) $($person.name.FamilyName)".Trim()
        $PartnerName = "$($person.name.FamilyNamePartnerPrefix) $($person.name.FamilyNamePartner)".Trim()

        switch ($person.name.convention) {
            'B' {
                return $FamilyName
             }
            'P' {
                return $PartnerName
             }
            'BP' {
                return "$($FamilyName) - $($PartnerName)"
             }
            'PB' {
                return "$($PartnerName) - $($FamilyName)"
            }
        }
    }
}


function Get-DisplayName {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $person
    )

    process {
        $SurName = Get-SurName -person $person

        return "$($person.name.NickName) $SurName"
    }
}


function Remove-StringLatinCharacters {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [string]
        $String
    )

    process {
        [Text.Encoding]::ASCII.GetString(
            [Text.Encoding]::GetEncoding("Cyrillic").GetBytes($String)
        )
    }
}


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
        Invoke-RestMethod @RestMethod
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

Write-Verbose 'Getting accessToken'
$splatGetTokenParams = @{
    TenantId     = $config.TenantId
    ClientId     = $config.ClientId
    ClientSecret = $config.ClientSecret
    Scope        = $config.Scope
}
$accessToken = (Get-LisaAccessToken @splatGetTokenParams).access_token
$authorizationHeaders = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
$authorizationHeaders.Add("Authorization", "Bearer $accessToken")
$authorizationHeaders.Add("Content-Type", "application/json")
$authorizationHeaders.Add("Mwp-Api-Version", "1.0")

# Mapping
$unique = $false
$Iteration = 0
$Domain =  $personObj.PrimaryContract.Custom.Suffix

while ($unique -eq $false) {
    $userPrincipalName = New-UserPrincipalName -person $p -domain $Domain -Iteration $Iteration

    $splatParams = @{
        Uri     = "$($config.BaseUrl)/Users?filter=startswith(userPrincipalName,'$userPrincipalName')"
        Method  = 'get'
        Headers = $authorizationHeaders
    }
    $userResponse = Invoke-RestMethod @splatParams

    if ($userResponse.count -eq 0) {
        Write-Verbose -Verbose "$userPrincipalName is uniek"
        $unique = $true
    }
    else {
        Write-Verbose -Verbose "$userPrincipalName is niet uniek"
        $iteration++
    }
}

# Build the Final Account object
$Account = @{
    givenName                = $p.Name.NickName
    surName                  = Get-SurName $p
    userPrincipalName        = $userPrincipalName
    displayName              = Get-DisplayName $p
    changePasswordNextSignIn = $True
    usageLocation            = "NL"
    preferredLanguage        = "nl"

    employeeId               = $p.ExternalId
    officeLocation           = $p.PrimaryContract.Department.DisplayName
    department               = $p.PrimaryContract.Department.DisplayName
    jobTitle                 = $p.PrimaryContract.Title.Name
    companyName              = $p.PrimaryContract.Organization.Name
    businessPhones           = @(
                                   $p.Contact.Business.Phone.Mobile
                               )
    accountEnabled           = $False
    mail                     = $userPrincipalName
    passWord                 = ''
}

$Success = $False

# Start Script
try {
    # Write-Verbose "Getting accessToken"

    # $splatGetTokenParams = @{
    #     TenantId     = $Config.TenantId
    #     ClientId     = $Config.ClientId
    #     ClientSecret = $Config.ClientSecret
    #     Scope        = $Config.Scope
    # }
    # $accessToken = (Get-LisaAccessToken @splatGetTokenParams).access_token

    # $authorizationHeaders = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    # $authorizationHeaders.Add("Authorization", "Bearer $($accessToken)")
    # $authorizationHeaders.Add("Content-Type", "application/json")
    # $authorizationHeaders.Add("Mwp-Api-Version", "1.0")

    # Create user
    Write-Verbose "Creating KPN Lisa account for '$($p.DisplayName)'"

    $Filter = "EmployeeID+eq+'$($p.ExternalId)'"

    $splatParams = @{
        Uri     = "$($Config.BaseUrl)/Users?filter=$($Filter)"
        Method  = 'get'
        Headers = $authorizationHeaders
    }
    $userResponse = Invoke-RestMethod @splatParams

    if ($userResponse.count -gt 1) {
        throw "Multiple accounts found with filter: $($Filter)"
    }

    if ($userResponse.count -eq 0) {
        $splatParams = @{
            Uri     = "$($Config.BaseUrl)/Users"
            Method  = 'POST'
            Body    = ($account | Select-Object @(
                    'givenName', 'surName', 'userPrincipalName',
                    'displayName','changePasswordNextSignIn',
                    'usageLocation', 'preferredLanguage'
            ) | ConvertTo-Json)
            Headers = $authorizationHeaders
        }

        if (-not($dryRun -eq $true)) {
            $userResponse = Invoke-RestMethod @splatParams
        }

        $aRef = $($userResponse.objectId)
        $account.passWord = $($userResponse.temporaryPassword)

        $AuditLogs.Add([PSCustomObject]@{
                Action  = "CreateAccount" # Optionally specify a different action for this audit log
                Message = "Created account for '$($p.DisplayName)'. Id: $($aRef)"
                IsError = $False
            })

        #Set Default WorkSpaceProfile
        $workSpaceProfileGuid = "500708ea-b69f-4f6c-83fc-dd5f382c308b" #WorkspaceProfile  "friendlyDisplayName": "Ontzorgd"

        $splatParams = @{
            Uri     = "$($Config.BaseUrl)/Users/$($aRef)/WorkspaceProfiles"
            Method  = 'PUT'
            Headers = $authorizationHeaders
            body    = ($workSpaceProfileGuid | ConvertTo-Json)
        }

        if (-not($dryRun -eq $true)) {
            [void] (Invoke-RestMethod @splatParams) #If 200 it returns a Empty String
        }

        Write-Verbose "Added Workspace profile [Ontzorgd]" -Verbose

    }
    else {
        $userResponse = $userResponse.value
        $aRef = $($userResponse.id)

        $AuditLogs.Add([PSCustomObject]@{
                Action  = "CreateAccount" # Optionally specify a different action for this audit log
                Message = "Correlated to account with id $($aRef)"
                IsError = $False
            })
    }

    if ($userResponse) {

        $splatParams = @{
            Uri     = "$($config.BaseUrl)/Users/$($aRef)/bulk"
            Method  = 'Patch'
            Headers = $authorizationHeaders
            body    = ($account | Select-Object -Property * -ExcludeProperty @(
                    'userPrincipalName', 'changePasswordNextSignIn',
                    'accountEnabled', 'preferredLanguage',
                    'usageLocation', 'mail', 'passWord'
                ) | ConvertTo-Json)
        }

        if (-not($dryRun -eq $true)) {
            [void] (Invoke-RestMethod @splatParams)
        }

        $AuditLogs.Add([PSCustomObject]@{
                Action  = "CreateAccount" # Optionally specify a different action for this audit log
                Message = "Updated account for '$($personObj.DisplayName)'. Id: $($aRef)"
                IsError = $False
            })

        # Set the manager
        if ($m) {
            $splatParams = @{
                Uri     = "$($Config.BaseUrl)/Users?filter=EmployeeID+eq+'$($m.ExternalId)'"
                Method  = 'GET'
                Headers = $authorizationHeaders
            }
            $managerResponse = Invoke-RestMethod @splatParams

            if ($managerResponse.count -eq 1) {
                $splatParams = @{
                    Uri     = "$($Config.BaseUrl)/Users/$($aRef)/Manager"
                    Method  = 'Put'
                    Body    = ($managerResponse.Value.id | ConvertTo-Json)
                    Headers = $authorizationHeaders
                }

                if (-not($dryRun -eq $true)) {
                    [void] (Invoke-RestMethod @splatParams)
                }

                Write-Verbose "Added Manager $($managerResponse.Value.displayName) to '$($p.DisplayName)'" -Verbose
            }
            else {
                throw  "Manager not Found '$($m.ExternalId)'"
            }
        }
        $Success = $true
    }
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage) [$($ex.ErrorDetails.Message)]"

    $auditLogs.Add([PSCustomObject]@{
            Action  = "CreateAccount" # Optionally specify a different action for this audit log
            Message = "Error creating account [$($account.DisplayName)]. Error Message: $($errorMessage.AuditErrorMessage)."
            IsError = $True
        })
}


$result = [PSCustomObject]@{
    Success          = $Success
    AccountReference = $aRef
    AuditLogs        = $AuditLogs
    Account          = $account

    # Optionally return data for use in other systems
    # ExportData = [PSCustomObject]@{
    #     DisplayName = $Account.DisplayName
    #     UserName    = $Account.UserName
    #     ExternalId  = $aRef
    # }
}

Write-Output $result | ConvertTo-Json -Depth 10
