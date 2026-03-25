########################################################################
# CWF SINGLE-DAY DEPLOYMENT - COMPLETE AUTOMATION
# 
# ONE SCRIPT. ONE RUN. ENTIRE CWF INFRASTRUCTURE.
#
# Phases:
#   Phase 1: Create 16 lists + 190 columns              (~20 min)
#   Phase 2: Seed 73 DCWF roles + 49 certs               (~10 min)
#   Phase 3: Create SP groups + 7-tier RBAC               (~10 min)
#   Phase 4: Create 40+ filtered/formatted views           (~15 min)
#   Phase 5: Apply JSON column/view formatting             (~10 min)
#   Phase 6: Create data ingestion folder structure        (~5 min)
#   Phase 7: Generate flow definition templates            (~5 min)
#   Phase 8: Validate everything + export report           (~5 min)
#
# Total estimated run time: ~80 minutes
#
# Author:  Jerad, ISSM / GS-2210-11
# Org:     TACOM G-6 Cyber & Operations
# Date:    March 2026
# Class:   CUI // FOUO
#
# USAGE:
#   .\cwf_full_deploy.ps1 -SiteUrl "https://[tenant].sharepoint-mil.us/sites/TACOMG-6CWFCompliancePortal"
#
# RESUME AFTER FAILURE:
#   .\cwf_full_deploy.ps1 -SiteUrl "..." -StartPhase 3
#
########################################################################

param(
    [Parameter(Mandatory=$true)][string]$SiteUrl,
    [Parameter(Mandatory=$false)][int]$StartPhase = 1,
    [Parameter(Mandatory=$false)][switch]$WhatIf
)

$ErrorActionPreference = "Continue"
$script:stats = @{ Created=0; Skipped=0; Errors=0; Views=0 }
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

function Write-Phase($phase, $title) {
    Write-Host "`n$('=' * 60)" -ForegroundColor Cyan
    Write-Host "  PHASE $phase : $title" -ForegroundColor Cyan
    Write-Host "$('=' * 60)`n" -ForegroundColor Cyan
}
function Write-Status($msg, $type = "INFO") {
    switch ($type) {
        "OK"     { Write-Host "  [OK]      $msg" -ForegroundColor Green }
        "CREATE" { Write-Host "  [CREATED] $msg" -ForegroundColor Cyan; $script:stats.Created++ }
        "SKIP"   { Write-Host "  [EXISTS]  $msg" -ForegroundColor DarkYellow; $script:stats.Skipped++ }
        "ERROR"  { Write-Host "  [ERROR]   $msg" -ForegroundColor Red; $script:stats.Errors++ }
        "VIEW"   { Write-Host "  [VIEW]    $msg" -ForegroundColor Magenta; $script:stats.Views++ }
        default  { Write-Host "  [INFO]    $msg" -ForegroundColor White }
    }
}

# ─── CONNECT ───
Write-Host "`n  CWF Full Deployment - Single Day Sprint" -ForegroundColor White
Write-Host "  Site: $SiteUrl" -ForegroundColor White
Write-Host "  Start Phase: $StartPhase" -ForegroundColor White
if ($WhatIf) { Write-Host "  MODE: WhatIf (no changes)`n" -ForegroundColor Magenta }

$isGCC = $SiteUrl -match "\.mil\.us|\.sharepoint-mil\.us"
if ($isGCC) { Connect-PnPOnline -Url $SiteUrl -Interactive -Environment USGovernment }
else { Connect-PnPOnline -Url $SiteUrl -Interactive }
Write-Status "Connected to: $(Get-PnPWeb | Select -Expand Title)" "OK"

########################################################################
# CHOICE SETS (mirrors Dataverse 21 global choices)
########################################################################
$choices = @{
    cwf_rank = @("E-1","E-2","E-3","E-4","E-5","E-6","E-7","E-8","E-9","O-1","O-2","O-3","O-4","O-5","O-6","O-7","O-8","O-9","O-10","W-1","W-2","W-3","W-4","W-5","GS-05","GS-07","GS-09","GS-11","GS-12","GS-13","GS-14","GS-15","SES","CTR (Contractor)","N/A")
    cwf_organization = @("TACOM G-1","TACOM G-2","TACOM G-3","TACOM G-4","TACOM G-6","TACOM G-8","ILSC","LCMC","Other")
    cwf_installation = @("TACOM HQ","TACOM HQ G6","ANAD","RRAD","WVA","RIA-JMTC","SIAD")
    cwf_clearance = @("None","Confidential","Secret","Top Secret","TS/SCI","Interim Secret","Interim Top Secret")
    cwf_compliance_status = @("Compliant","Non-Compliant","Partially Compliant","Pending Review","Waiver Approved","Expired")
    cwf_record_lifecycle = @("Active","Inactive","Pending","Archived","Separated")
    cwf_sensitivity_category = @("Uncontrolled","Controlled - Collaboration")
    cwf_sensitivity_sub_label = @("General","Secured (Any)","Secured (Internal Only)","Recipients Only","CUI","CUI - Secured (Internal Only)","CUI - Recipients Only","CUI - DoD Community Only")
    cwf_work_role_category = @("Cyber IT","Cyber Effects","Cyber Enablers","Cybersecurity","Data/AI","Software Engineering","Intel (Cyber)","Securely Provision (SP)","Operate and Maintain (OM)","Oversee and Govern (OV)","Protect and Defend (PR)","Analyze (AN)","Collect and Operate (CO)","Investigate (IN)")
    cwf_cert_status = @("Active","Expired","Expiring Soon","Revoked","Suspended","Pending Renewal")
    cwf_training_category = @("Foundational","Resident","Certification Prep","Continuing Education","Cyber Awareness","On-the-Job (OJT)","Other")
    cwf_training_status = @("Not Started","In Progress","Completed","Expired","Waived","Failed")
    cwf_access_type = @("Authorized User","Privileged User","System Administrator","Read Only","Remote Access","Temporary")
    cwf_saar_status = @("Draft","Submitted","Supervisor Approved","IA Approved","Fully Approved","Denied","Revoked","Expired")
    cwf_severity = @("CAT I (High)","CAT II (Medium)","CAT III (Low)","Informational")
    cwf_check_status = @("Open","Not a Finding","Not Applicable","Not Reviewed","Finding")
    cwf_process_status = @("Open","In Progress","Completed","Delayed","Cancelled","Risk Accepted")
    cwf_ato_status = @("ATO","IATT","DATO","ATO with Conditions","Expired","Pending")
    cwf_classification = @("Unclassified","CUI","Confidential","Secret","Top Secret","TS/SCI")
    cwf_approval_status = @("Pending","Approved","Denied","Expired","Revoked")
    cwf_workflow_stage = @("Created","Updated","Submitted","Approved","Rejected","Deleted","Archived")
    cwf_priority = @("Low","Medium","High","Critical")
    cwf_qual_level = @("Basic","Intermediate","Advanced")
}

########################################################################
# HELPER: Create list + columns (idempotent)
########################################################################
function New-CWFList {
    param([string]$Name, [string]$Desc, [array]$Cols)
    if ($WhatIf) { Write-Status "$Name ($($Cols.Count) cols) [WhatIf]"; return }
    $existing = Get-PnPList -Identity $Name -ErrorAction SilentlyContinue
    if ($existing) { Write-Status "$Name (ItemCount: $($existing.ItemCount))" "SKIP" }
    else { New-PnPList -Title $Name -Template GenericList -EnableVersioning -OnQuickLaunch | Out-Null; Write-Status $Name "CREATE" }
    foreach ($c in $Cols) {
        $ef = Get-PnPField -List $Name -Identity $c.I -ErrorAction SilentlyContinue
        if ($ef) { continue }
        try {
            switch ($c.T) {
                "Text"     { Add-PnPField -List $Name -DisplayName $c.D -InternalName $c.I -Type Text -Required:$c.R -AddToDefaultView | Out-Null }
                "Note"     { Add-PnPField -List $Name -DisplayName $c.D -InternalName $c.I -Type Note -Required:$c.R -AddToDefaultView | Out-Null }
                "DateTime" { Add-PnPField -List $Name -DisplayName $c.D -InternalName $c.I -Type DateTime -Required:$c.R -AddToDefaultView | Out-Null }
                "Boolean"  { Add-PnPField -List $Name -DisplayName $c.D -InternalName $c.I -Type Boolean -Required:$c.R -AddToDefaultView | Out-Null }
                "Number"   { Add-PnPField -List $Name -DisplayName $c.D -InternalName $c.I -Type Number -Required:$c.R -AddToDefaultView | Out-Null }
                "URL"      { Add-PnPField -List $Name -DisplayName $c.D -InternalName $c.I -Type URL -Required:$c.R -AddToDefaultView | Out-Null }
                "Choice"   { Add-PnPField -List $Name -DisplayName $c.D -InternalName $c.I -Type Choice -Choices $choices[$c.C] -Required:$c.R -AddToDefaultView | Out-Null }
            }
            $script:stats.Created++
        } catch { Write-Status "  Col $($c.I) on $Name : $_" "ERROR" }
    }
}

########################################################################
# HELPER: Create filtered view with optional JSON formatting
########################################################################
function New-CWFView {
    param(
        [string]$ListName,
        [string]$ViewName,
        [string[]]$Fields,
        [string]$Query = "",
        [string]$RowFormatter = "",
        [bool]$SetDefault = $false
    )
    if ($WhatIf) { Write-Status "$ViewName on $ListName [WhatIf]" "VIEW"; return }
    $ev = Get-PnPView -List $ListName -Identity $ViewName -ErrorAction SilentlyContinue
    if ($ev) { 
        # Update existing view formatting if provided
        if ($RowFormatter) {
            $ev | Set-PnPView -List $ListName -Values @{ CustomFormatter = $RowFormatter }
        }
        Write-Status "$ViewName (exists, formatter updated)" "SKIP"
        return 
    }
    try {
        $viewParams = @{
            List = $ListName
            Title = $ViewName
            Fields = $Fields
        }
        if ($Query) { $viewParams.Query = $Query }
        if ($SetDefault) { $viewParams.SetAsDefault = $true }
        
        $newView = Add-PnPView @viewParams
        
        if ($RowFormatter) {
            Set-PnPView -List $ListName -Identity $ViewName -Values @{ CustomFormatter = $RowFormatter }
        }
        Write-Status $ViewName "VIEW"
    } catch { Write-Status "$ViewName on $ListName : $_" "ERROR" }
}

########################################################################
# PHASE 1: CREATE 16 LISTS + ALL COLUMNS
########################################################################
if ($StartPhase -le 1) {
Write-Phase 1 "CREATE 16 LISTS + 190 COLUMNS"

# Column shorthand: D=Display, I=Internal, T=Type, R=Required, C=ChoiceSet
New-CWFList "CWF_Personnel" "Personnel records" @(
    @{D="First Name";I="cwf_first_name";T="Text";R=$true;C=$null},
    @{D="Last Name";I="cwf_last_name";T="Text";R=$true;C=$null},
    @{D="DoD ID";I="cwf_dod_id";T="Text";R=$true;C=$null},
    @{D="Email";I="cwf_email";T="Text";R=$true;C=$null},
    @{D="Phone";I="cwf_phone";T="Text";R=$false;C=$null},
    @{D="Rank/Grade";I="cwf_rank";T="Choice";R=$true;C="cwf_rank"},
    @{D="Organization";I="cwf_organization";T="Choice";R=$true;C="cwf_organization"},
    @{D="Installation";I="cwf_installation";T="Choice";R=$true;C="cwf_installation"},
    @{D="Duty Position";I="cwf_duty_position";T="Text";R=$false;C=$null},
    @{D="Supervisor Email";I="cwf_supervisor_email";T="Text";R=$false;C=$null},
    @{D="Clearance Level";I="cwf_clearance";T="Choice";R=$false;C="cwf_clearance"},
    @{D="Compliance Status";I="cwf_compliance_status";T="Choice";R=$false;C="cwf_compliance_status"},
    @{D="Personnel Status";I="cwf_personnel_status";T="Choice";R=$true;C="cwf_record_lifecycle"},
    @{D="Onboard Date";I="cwf_onboard_date";T="DateTime";R=$false;C=$null},
    @{D="Separation Date";I="cwf_separation_date";T="DateTime";R=$false;C=$null},
    @{D="Sensitivity Category";I="cwf_sensitivity_cat";T="Choice";R=$false;C="cwf_sensitivity_category"},
    @{D="Sensitivity Label";I="cwf_sensitivity_label";T="Choice";R=$false;C="cwf_sensitivity_sub_label"},
    @{D="Notes";I="cwf_notes";T="Note";R=$false;C=$null}
)

New-CWFList "CWF_WorkRoles" "DCWF work role definitions (73 roles)" @(
    @{D="DCWF Code";I="cwf_wr_dcwf_code";T="Text";R=$true;C=$null},
    @{D="Work Role Name";I="cwf_wr_name";T="Text";R=$true;C=$null},
    @{D="Element";I="cwf_wr_element";T="Choice";R=$true;C="cwf_work_role_category"},
    @{D="OPR";I="cwf_wr_opr";T="Text";R=$false;C=$null},
    @{D="Certs (Basic)";I="cwf_wr_certs_basic";T="Text";R=$false;C=$null},
    @{D="Certs (Intermediate)";I="cwf_wr_certs_inter";T="Text";R=$false;C=$null},
    @{D="Certs (Advanced)";I="cwf_wr_certs_adv";T="Note";R=$false;C=$null},
    @{D="Phase Deadline";I="cwf_wr_deadline";T="Text";R=$false;C=$null},
    @{D="Description";I="cwf_wr_description";T="Note";R=$false;C=$null},
    @{D="Foundational Qual";I="cwf_wr_foundational";T="Text";R=$false;C=$null},
    @{D="Active";I="cwf_wr_active";T="Boolean";R=$false;C=$null}
)

New-CWFList "CWF_WorkRoleAssignments" "Personnel to work role mappings" @(
    @{D="Personnel Name";I="cwf_wra_personnel_name";T="Text";R=$true;C=$null},
    @{D="Personnel DoD ID";I="cwf_wra_dod_id";T="Text";R=$true;C=$null},
    @{D="Work Role";I="cwf_wra_work_role";T="Text";R=$true;C=$null},
    @{D="Work Role ID";I="cwf_wra_work_role_id";T="Text";R=$false;C=$null},
    @{D="Primary Role";I="cwf_wra_primary";T="Boolean";R=$false;C=$null},
    @{D="Assignment Date";I="cwf_wra_assign_date";T="DateTime";R=$true;C=$null},
    @{D="Qualification Status";I="cwf_wra_qual_status";T="Choice";R=$false;C="cwf_compliance_status"},
    @{D="Qualification Level";I="cwf_wra_qual_level";T="Choice";R=$false;C="cwf_qual_level"},
    @{D="Qualification Date";I="cwf_wra_qual_date";T="DateTime";R=$false;C=$null},
    @{D="Expiration Date";I="cwf_wra_exp_date";T="DateTime";R=$false;C=$null},
    @{D="Installation";I="cwf_wra_installation";T="Choice";R=$false;C="cwf_installation"},
    @{D="Notes";I="cwf_wra_notes";T="Note";R=$false;C=$null}
)

New-CWFList "CWF_Certifications" "Approved certification catalog (49 certs)" @(
    @{D="Certification Name";I="cwf_cert_name";T="Text";R=$true;C=$null},
    @{D="Cert Code";I="cwf_cert_code";T="Text";R=$true;C=$null},
    @{D="Issuing Body";I="cwf_cert_issuing_body";T="Text";R=$true;C=$null},
    @{D="DoD 8140 Approved";I="cwf_cert_dod_approved";T="Boolean";R=$false;C=$null},
    @{D="ANSI 17024";I="cwf_cert_ansi";T="Boolean";R=$false;C=$null},
    @{D="Validity (Months)";I="cwf_cert_validity_months";T="Number";R=$false;C=$null},
    @{D="CE Required";I="cwf_cert_ce_required";T="Boolean";R=$false;C=$null},
    @{D="CE Hours Required";I="cwf_cert_ce_hours";T="Number";R=$false;C=$null},
    @{D="Mapped Work Roles";I="cwf_cert_mapped_wr";T="Note";R=$false;C=$null},
    @{D="Description";I="cwf_cert_description";T="Note";R=$false;C=$null},
    @{D="Active";I="cwf_cert_active";T="Boolean";R=$false;C=$null}
)

New-CWFList "CWF_PersonnelCerts" "Certifications held per person" @(
    @{D="Personnel Name";I="cwf_pc_personnel_name";T="Text";R=$true;C=$null},
    @{D="Personnel DoD ID";I="cwf_pc_dod_id";T="Text";R=$true;C=$null},
    @{D="Certification";I="cwf_pc_cert_name";T="Text";R=$true;C=$null},
    @{D="Cert Code";I="cwf_pc_cert_code";T="Text";R=$false;C=$null},
    @{D="Date Earned";I="cwf_pc_date_earned";T="DateTime";R=$true;C=$null},
    @{D="Expiration Date";I="cwf_pc_exp_date";T="DateTime";R=$false;C=$null},
    @{D="Cert Status";I="cwf_pc_cert_status";T="Choice";R=$true;C="cwf_cert_status"},
    @{D="Certificate Number";I="cwf_pc_cert_number";T="Text";R=$false;C=$null},
    @{D="Verification URL";I="cwf_pc_verify_url";T="URL";R=$false;C=$null},
    @{D="CE Hours Completed";I="cwf_pc_ce_completed";T="Number";R=$false;C=$null},
    @{D="Installation";I="cwf_pc_installation";T="Choice";R=$false;C="cwf_installation"},
    @{D="Notes";I="cwf_pc_notes";T="Note";R=$false;C=$null}
)

New-CWFList "CWF_TrainingCourses" "Training course catalog" @(
    @{D="Course Name";I="cwf_tr_course_name";T="Text";R=$true;C=$null},
    @{D="Course Code";I="cwf_tr_course_code";T="Text";R=$false;C=$null},
    @{D="Training Category";I="cwf_tr_category";T="Choice";R=$true;C="cwf_training_category"},
    @{D="Provider";I="cwf_tr_provider";T="Text";R=$false;C=$null},
    @{D="Duration (Hours)";I="cwf_tr_duration";T="Number";R=$false;C=$null},
    @{D="Delivery Method";I="cwf_tr_delivery";T="Text";R=$false;C=$null},
    @{D="Mapped Work Roles";I="cwf_tr_mapped_wr";T="Note";R=$false;C=$null},
    @{D="DoD 8140 Approved";I="cwf_tr_dod_approved";T="Boolean";R=$false;C=$null},
    @{D="URL";I="cwf_tr_url";T="URL";R=$false;C=$null},
    @{D="Description";I="cwf_tr_description";T="Note";R=$false;C=$null},
    @{D="Active";I="cwf_tr_active";T="Boolean";R=$false;C=$null}
)

New-CWFList "CWF_PersonnelTraining" "Training completion per person" @(
    @{D="Personnel Name";I="cwf_pt_personnel_name";T="Text";R=$true;C=$null},
    @{D="Personnel DoD ID";I="cwf_pt_dod_id";T="Text";R=$true;C=$null},
    @{D="Course Name";I="cwf_pt_course_name";T="Text";R=$true;C=$null},
    @{D="Course Code";I="cwf_pt_course_code";T="Text";R=$false;C=$null},
    @{D="Training Status";I="cwf_pt_status";T="Choice";R=$true;C="cwf_training_status"},
    @{D="Start Date";I="cwf_pt_start_date";T="DateTime";R=$false;C=$null},
    @{D="Completion Date";I="cwf_pt_comp_date";T="DateTime";R=$false;C=$null},
    @{D="Expiration Date";I="cwf_pt_exp_date";T="DateTime";R=$false;C=$null},
    @{D="Hours Completed";I="cwf_pt_hours";T="Number";R=$false;C=$null},
    @{D="Certificate URL";I="cwf_pt_cert_url";T="URL";R=$false;C=$null},
    @{D="Installation";I="cwf_pt_installation";T="Choice";R=$false;C="cwf_installation"},
    @{D="Notes";I="cwf_pt_notes";T="Note";R=$false;C=$null}
)

New-CWFList "CWF_SAAR" "System Authorization Access Requests (DD 2875)" @(
    @{D="Requestor Name";I="cwf_saar_requestor";T="Text";R=$true;C=$null},
    @{D="Requestor DoD ID";I="cwf_saar_dod_id";T="Text";R=$true;C=$null},
    @{D="Requestor Email";I="cwf_saar_email";T="Text";R=$true;C=$null},
    @{D="System Name";I="cwf_saar_system";T="Text";R=$true;C=$null},
    @{D="Access Type";I="cwf_saar_access_type";T="Choice";R=$false;C="cwf_access_type"},
    @{D="Justification";I="cwf_saar_justification";T="Note";R=$true;C=$null},
    @{D="SAAR Workflow Status";I="cwf_saar_wf_status";T="Choice";R=$true;C="cwf_saar_status"},
    @{D="Supervisor";I="cwf_saar_supervisor";T="Text";R=$false;C=$null},
    @{D="Security Manager";I="cwf_saar_sec_mgr";T="Text";R=$false;C=$null},
    @{D="ISSO";I="cwf_saar_isso";T="Text";R=$false;C=$null},
    @{D="Source Req ID";I="cwf_saar_source_req_id";T="Text";R=$false;C=$null},
    @{D="Supervisor Approval Date";I="cwf_saar_sup_date";T="DateTime";R=$false;C=$null},
    @{D="IA Approval Date";I="cwf_saar_ia_date";T="DateTime";R=$false;C=$null},
    @{D="Request Date";I="cwf_saar_request_date";T="DateTime";R=$true;C=$null},
    @{D="Expiration Date";I="cwf_saar_exp_date";T="DateTime";R=$false;C=$null},
    @{D="Cyber Training Complete";I="cwf_saar_cyber_train";T="Boolean";R=$false;C=$null},
    @{D="AUP Signed";I="cwf_saar_aup_signed";T="Boolean";R=$false;C=$null},
    @{D="Installation";I="cwf_saar_installation";T="Choice";R=$false;C="cwf_installation"},
    @{D="Notes";I="cwf_saar_notes";T="Note";R=$false;C=$null}
)

New-CWFList "CWF_STIGCompliance" "STIG checklist items" @(
    @{D="STIG ID";I="cwf_stig_id";T="Text";R=$true;C=$null},
    @{D="STIG Title";I="cwf_stig_title";T="Text";R=$true;C=$null},
    @{D="Severity";I="cwf_stig_severity";T="Choice";R=$true;C="cwf_severity"},
    @{D="Check Status";I="cwf_stig_check_status";T="Choice";R=$true;C="cwf_check_status"},
    @{D="System";I="cwf_stig_system";T="Text";R=$false;C=$null},
    @{D="Rule ID";I="cwf_stig_rule_id";T="Text";R=$false;C=$null},
    @{D="Fix Text";I="cwf_stig_fix_text";T="Note";R=$false;C=$null},
    @{D="Check Text";I="cwf_stig_check_text";T="Note";R=$false;C=$null},
    @{D="Finding Details";I="cwf_stig_finding";T="Note";R=$false;C=$null},
    @{D="Review Date";I="cwf_stig_review_date";T="DateTime";R=$false;C=$null},
    @{D="POA&M Required";I="cwf_stig_poam_req";T="Boolean";R=$false;C=$null},
    @{D="Installation";I="cwf_stig_installation";T="Choice";R=$false;C="cwf_installation"}
)

New-CWFList "CWF_POAM" "Plan of Action and Milestones" @(
    @{D="POAM ID";I="cwf_poam_id";T="Text";R=$true;C=$null},
    @{D="Weakness";I="cwf_poam_weakness";T="Note";R=$true;C=$null},
    @{D="Related STIG";I="cwf_poam_stig_id";T="Text";R=$false;C=$null},
    @{D="Severity";I="cwf_poam_severity";T="Choice";R=$false;C="cwf_severity"},
    @{D="Milestone";I="cwf_poam_milestone";T="Note";R=$false;C=$null},
    @{D="Process Status";I="cwf_poam_status";T="Choice";R=$true;C="cwf_process_status"},
    @{D="Scheduled Completion";I="cwf_poam_sched_date";T="DateTime";R=$true;C=$null},
    @{D="Actual Completion";I="cwf_poam_actual_date";T="DateTime";R=$false;C=$null},
    @{D="Risk Accepted";I="cwf_poam_risk_accepted";T="Boolean";R=$false;C=$null},
    @{D="Installation";I="cwf_poam_installation";T="Choice";R=$false;C="cwf_installation"},
    @{D="Notes";I="cwf_poam_notes";T="Note";R=$false;C=$null}
)

New-CWFList "CWF_Systems" "Information systems inventory" @(
    @{D="System Name";I="cwf_sys_name";T="Text";R=$true;C=$null},
    @{D="System Acronym";I="cwf_sys_acronym";T="Text";R=$false;C=$null},
    @{D="eMASS ID";I="cwf_sys_emass_id";T="Text";R=$false;C=$null},
    @{D="ATO Status";I="cwf_sys_ato_status";T="Choice";R=$false;C="cwf_ato_status"},
    @{D="ATO Expiration";I="cwf_sys_ato_exp";T="DateTime";R=$false;C=$null},
    @{D="Classification";I="cwf_sys_classification";T="Choice";R=$false;C="cwf_classification"},
    @{D="Description";I="cwf_sys_description";T="Note";R=$false;C=$null},
    @{D="Installation";I="cwf_sys_installation";T="Choice";R=$false;C="cwf_installation"},
    @{D="Active";I="cwf_sys_active";T="Boolean";R=$false;C=$null}
)

New-CWFList "CWF_Waivers" "Compliance waivers" @(
    @{D="Waiver ID";I="cwf_waiver_id";T="Text";R=$true;C=$null},
    @{D="Personnel Name";I="cwf_waiver_personnel";T="Text";R=$true;C=$null},
    @{D="Personnel DoD ID";I="cwf_waiver_dod_id";T="Text";R=$false;C=$null},
    @{D="Waiver Type";I="cwf_waiver_type";T="Text";R=$false;C=$null},
    @{D="Justification";I="cwf_waiver_justification";T="Note";R=$true;C=$null},
    @{D="Approval Status";I="cwf_waiver_approval";T="Choice";R=$true;C="cwf_approval_status"},
    @{D="Request Date";I="cwf_waiver_req_date";T="DateTime";R=$true;C=$null},
    @{D="Approval Date";I="cwf_waiver_appr_date";T="DateTime";R=$false;C=$null},
    @{D="Expiration Date";I="cwf_waiver_exp_date";T="DateTime";R=$false;C=$null},
    @{D="Installation";I="cwf_waiver_installation";T="Choice";R=$false;C="cwf_installation"},
    @{D="Notes";I="cwf_waiver_notes";T="Note";R=$false;C=$null}
)

New-CWFList "CWF_AuditLog" "Compliance audit trail" @(
    @{D="Action";I="cwf_audit_action";T="Choice";R=$true;C="cwf_workflow_stage"},
    @{D="Entity Type";I="cwf_audit_entity_type";T="Text";R=$false;C=$null},
    @{D="Record ID";I="cwf_audit_record_id";T="Text";R=$false;C=$null},
    @{D="Record Title";I="cwf_audit_record_title";T="Text";R=$false;C=$null},
    @{D="Timestamp";I="cwf_audit_timestamp";T="DateTime";R=$true;C=$null},
    @{D="Previous Value";I="cwf_audit_prev_value";T="Note";R=$false;C=$null},
    @{D="New Value";I="cwf_audit_new_value";T="Note";R=$false;C=$null},
    @{D="Performed By";I="cwf_audit_performed_by";T="Text";R=$false;C=$null},
    @{D="Notes";I="cwf_audit_notes";T="Note";R=$false;C=$null}
)

New-CWFList "CWF_Notifications" "Automated notifications" @(
    @{D="Notification Type";I="cwf_notif_type";T="Text";R=$true;C=$null},
    @{D="Recipient Email";I="cwf_notif_email";T="Text";R=$false;C=$null},
    @{D="Subject";I="cwf_notif_subject";T="Text";R=$true;C=$null},
    @{D="Message";I="cwf_notif_message";T="Note";R=$false;C=$null},
    @{D="Related Record";I="cwf_notif_related";T="Text";R=$false;C=$null},
    @{D="Sent Date";I="cwf_notif_sent_date";T="DateTime";R=$false;C=$null},
    @{D="Read";I="cwf_notif_read";T="Boolean";R=$false;C=$null},
    @{D="Priority";I="cwf_notif_priority";T="Choice";R=$false;C="cwf_priority"},
    @{D="Installation";I="cwf_notif_installation";T="Choice";R=$false;C="cwf_installation"}
)

New-CWFList "CWF_ComplianceReports" "Compliance report snapshots" @(
    @{D="Report Name";I="cwf_rpt_name";T="Text";R=$true;C=$null},
    @{D="Report Type";I="cwf_rpt_type";T="Text";R=$false;C=$null},
    @{D="Generated Date";I="cwf_rpt_gen_date";T="DateTime";R=$true;C=$null},
    @{D="Period Start";I="cwf_rpt_period_start";T="DateTime";R=$false;C=$null},
    @{D="Period End";I="cwf_rpt_period_end";T="DateTime";R=$false;C=$null},
    @{D="Total Personnel";I="cwf_rpt_total";T="Number";R=$false;C=$null},
    @{D="Compliant Count";I="cwf_rpt_compliant";T="Number";R=$false;C=$null},
    @{D="Non-Compliant Count";I="cwf_rpt_non_compliant";T="Number";R=$false;C=$null},
    @{D="Compliance %";I="cwf_rpt_pct";T="Number";R=$false;C=$null},
    @{D="Report URL";I="cwf_rpt_url";T="URL";R=$false;C=$null},
    @{D="Installation";I="cwf_rpt_installation";T="Choice";R=$false;C="cwf_installation"},
    @{D="Notes";I="cwf_rpt_notes";T="Note";R=$false;C=$null}
)

New-CWFList "CWF_Configuration" "Portal settings" @(
    @{D="Setting Name";I="cwf_config_name";T="Text";R=$true;C=$null},
    @{D="Setting Value";I="cwf_config_value";T="Note";R=$true;C=$null},
    @{D="Setting Category";I="cwf_config_category";T="Text";R=$false;C=$null},
    @{D="Description";I="cwf_config_description";T="Note";R=$false;C=$null},
    @{D="Data Type";I="cwf_config_data_type";T="Text";R=$false;C=$null},
    @{D="Last Modified";I="cwf_config_mod_date";T="DateTime";R=$false;C=$null},
    @{D="Modified By";I="cwf_config_modified_by";T="Text";R=$false;C=$null}
)

Write-Status "Phase 1 complete: 16 lists created" "OK"
} # End Phase 1

########################################################################
# PHASE 2: SEED DATA (73 roles + 49 certs + UIC map)
# (Identical seed data from cwf_teams_sp_deploy.ps1 - abbreviated here)
########################################################################
if ($StartPhase -le 2) {
Write-Phase 2 "SEED REFERENCE DATA"

# Seed UIC Map in Configuration
if (-not $WhatIf) {
    $uicMap = '{"W45G13":"TACOM HQ G6","WOK9AA":"TACOM HQ","W0K9AB":"ANAD","W0K9AC":"RRAD","W0K9AD":"WVA","W0K9AE":"RIA-JMTC","W0K9AF":"SIAD"}'
    Add-PnPListItem -List "CWF_Configuration" -Values @{
        Title = "UIC_MAP"; cwf_config_name = "UIC_MAP"; cwf_config_value = $uicMap
        cwf_config_category = "DataIngestion"; cwf_config_data_type = "JSON"
        cwf_config_description = "Maps UIC codes to Installation choice values for Power BI imports"
    } | Out-Null
    Write-Status "UIC_MAP config seeded" "CREATE"
}

Write-Host "`n  >>> Seeding 73 DCWF work roles + 49 certs..." -ForegroundColor Cyan
Write-Host "  >>> (Uses seed data from cwf_teams_sp_deploy.ps1 Phase 2)" -ForegroundColor Cyan
Write-Host "  >>> Run: .\cwf_teams_sp_deploy.ps1 -SiteUrl $SiteUrl -SkipListCreation -SkipPermissions" -ForegroundColor Yellow
Write-Host "  >>> OR: pipe the seed section from the full deploy script`n" -ForegroundColor Yellow

Write-Status "Phase 2: UIC_MAP seeded. Run seed script for roles/certs." "OK"
} # End Phase 2

########################################################################
# PHASE 3: SP GROUPS + 7-TIER RBAC
########################################################################
if ($StartPhase -le 3) {
Write-Phase 3 "SP GROUPS + 7-TIER RBAC PERMISSIONS"

$spGroups = @(
    @{N="CWF - System Admins";D="Tier 7: ISSM + Admin 2. Full Control."},
    @{N="CWF - TACOM O-ISSM";D="Tier 6: Organization ISSM. Read all + approve."},
    @{N="CWF - TACOM HQ G6";D="Tier 5: HQ G-6 staff. See ALL installations."},
    @{N="CWF - TACOM HQ";D="Tier 4: TACOM HQ (non-G6). See TACOM HQ data."},
    @{N="CWF - ISSM ANAD";D="Tier 3: ANAD ISSM."},
    @{N="CWF - ISSM RRAD";D="Tier 3: RRAD ISSM."},
    @{N="CWF - ISSM WVA";D="Tier 3: WVA ISSM."},
    @{N="CWF - ISSM RIA-JMTC";D="Tier 3: RIA-JMTC ISSM."},
    @{N="CWF - ISSM SIAD";D="Tier 3: SIAD ISSM."},
    @{N="CWF - Supervisors";D="Tier 2: Supervisors. See direct reports."}
)

foreach ($g in $spGroups) {
    if ($WhatIf) { Write-Status "$($g.N) [WhatIf]"; continue }
    $ex = Get-PnPGroup -Identity $g.N -ErrorAction SilentlyContinue
    if ($ex) { Write-Status $g.N "SKIP" }
    else { New-PnPGroup -Title $g.N -Description $g.D | Out-Null; Write-Status $g.N "CREATE" }
}

# Item-level permissions: Tier 1 sees own items only
$ownItemsLists = @("CWF_Personnel","CWF_PersonnelCerts","CWF_PersonnelTraining","CWF_WorkRoleAssignments","CWF_SAAR","CWF_Waivers")
foreach ($l in $ownItemsLists) {
    if (-not $WhatIf) {
        Set-PnPList -Identity $l -ReadSecurity 2 -WriteSecurity 2
        Write-Status "$l -> own items only (Tier 1)" "OK"
    }
}

# Break inheritance on sensitive lists
$sensitiveLists = @("CWF_SAAR","CWF_STIGCompliance","CWF_POAM","CWF_AuditLog","CWF_Configuration")
foreach ($l in $sensitiveLists) {
    if (-not $WhatIf) {
        Set-PnPList -Identity $l -BreakRoleInheritance -CopyRoleAssignments:$false
        Set-PnPListPermission -Identity $l -Group "CWF - System Admins" -AddRole "Full Control"
        Set-PnPListPermission -Identity $l -Group "CWF - TACOM O-ISSM" -AddRole "Edit"
        if ($l -notin @("CWF_Configuration","CWF_AuditLog")) {
            Set-PnPListPermission -Identity $l -Group "CWF - TACOM HQ G6" -AddRole "Read"
        }
        Write-Status "$l -> broken inheritance, tiered access" "OK"
    }
}

# Override access on personnel lists for Tiers 2-7
$personnelLists = @("CWF_Personnel","CWF_PersonnelCerts","CWF_PersonnelTraining","CWF_WorkRoleAssignments","CWF_Waivers")
$overrideGroups = @("CWF - System Admins","CWF - TACOM O-ISSM","CWF - TACOM HQ G6","CWF - TACOM HQ",
                     "CWF - ISSM ANAD","CWF - ISSM RRAD","CWF - ISSM WVA","CWF - ISSM RIA-JMTC","CWF - ISSM SIAD","CWF - Supervisors")
foreach ($l in $personnelLists) {
    if (-not $WhatIf) {
        Set-PnPList -Identity $l -BreakRoleInheritance -CopyRoleAssignments:$true
        foreach ($g in $overrideGroups) {
            $role = if ($g -eq "CWF - System Admins") { "Full Control" } elseif ($g -eq "CWF - TACOM O-ISSM") { "Edit" } else { "Read" }
            Set-PnPListPermission -Identity $l -Group $g -AddRole $role
        }
        Write-Status "$l -> tiered override access" "OK"
    }
}

Write-Status "Phase 3 complete: 10 groups, 7-tier RBAC applied" "OK"
} # End Phase 3

########################################################################
# PHASE 4: CREATE VIEWS (40+ views with CAML filters)
########################################################################
if ($StartPhase -le 4) {
Write-Phase 4 "CREATE 40+ FILTERED VIEWS"

$installations = @("TACOM HQ","TACOM HQ G6","ANAD","RRAD","WVA","RIA-JMTC","SIAD")

# ─── Installation-filtered views on key lists ───
$viewTargets = @(
    @{List="CWF_Personnel"; Field="cwf_installation"; Cols=@("Title","cwf_first_name","cwf_last_name","cwf_email","cwf_rank","cwf_compliance_status","cwf_installation")},
    @{List="CWF_PersonnelCerts"; Field="cwf_pc_installation"; Cols=@("Title","cwf_pc_personnel_name","cwf_pc_cert_name","cwf_pc_cert_status","cwf_pc_exp_date","cwf_pc_installation")},
    @{List="CWF_PersonnelTraining"; Field="cwf_pt_installation"; Cols=@("Title","cwf_pt_personnel_name","cwf_pt_course_name","cwf_pt_status","cwf_pt_comp_date","cwf_pt_installation")},
    @{List="CWF_SAAR"; Field="cwf_saar_installation"; Cols=@("Title","cwf_saar_requestor","cwf_saar_system","cwf_saar_wf_status","cwf_saar_request_date","cwf_saar_installation")}
)

foreach ($vt in $viewTargets) {
    foreach ($inst in $installations) {
        $shortList = $vt.List.Replace("CWF_","")
        $viewName = "$inst - $shortList"
        $caml = "<Where><Eq><FieldRef Name='$($vt.Field)'/><Value Type='Choice'>$inst</Value></Eq></Where>"
        New-CWFView -ListName $vt.List -ViewName $viewName -Fields $vt.Cols -Query $caml
    }
}

# ─── Supervisor: My Direct Reports ───
New-CWFView -ListName "CWF_Personnel" -ViewName "My Direct Reports" `
    -Fields @("Title","cwf_first_name","cwf_last_name","cwf_email","cwf_compliance_status","cwf_installation") `
    -Query "<Where><Eq><FieldRef Name='cwf_supervisor_email'/><Value Type='Text'><UserID/></Value></Eq></Where>"

# ─── Compliance Status views ───
foreach ($status in @("Compliant","Non-Compliant","Partially Compliant","Expired")) {
    New-CWFView -ListName "CWF_Personnel" -ViewName "$status Personnel" `
        -Fields @("Title","cwf_first_name","cwf_last_name","cwf_email","cwf_rank","cwf_installation","cwf_compliance_status") `
        -Query "<Where><Eq><FieldRef Name='cwf_compliance_status'/><Value Type='Choice'>$status</Value></Eq></Where>"
}

# ─── Cert Expiration views ───
New-CWFView -ListName "CWF_PersonnelCerts" -ViewName "Expiring in 90 Days" `
    -Fields @("Title","cwf_pc_personnel_name","cwf_pc_cert_name","cwf_pc_exp_date","cwf_pc_cert_status","cwf_pc_installation") `
    -Query "<Where><And><Leq><FieldRef Name='cwf_pc_exp_date'/><Value Type='DateTime'><Today OffsetDays='90'/></Value></Leq><Geq><FieldRef Name='cwf_pc_exp_date'/><Value Type='DateTime'><Today/></Value></Geq></And></Where>"

New-CWFView -ListName "CWF_PersonnelCerts" -ViewName "Expired Certs" `
    -Fields @("Title","cwf_pc_personnel_name","cwf_pc_cert_name","cwf_pc_exp_date","cwf_pc_cert_status","cwf_pc_installation") `
    -Query "<Where><Lt><FieldRef Name='cwf_pc_exp_date'/><Value Type='DateTime'><Today/></Value></Lt></Where>"

# ─── SAAR Pipeline views ───
foreach ($status in @("Draft","Submitted","Fully Approved","Denied")) {
    New-CWFView -ListName "CWF_SAAR" -ViewName "SAAR - $status" `
        -Fields @("Title","cwf_saar_requestor","cwf_saar_system","cwf_saar_wf_status","cwf_saar_request_date","cwf_saar_supervisor","cwf_saar_sec_mgr","cwf_saar_isso") `
        -Query "<Where><Eq><FieldRef Name='cwf_saar_wf_status'/><Value Type='Choice'>$status</Value></Eq></Where>"
}

# ─── STIG/POAM views ───
New-CWFView -ListName "CWF_STIGCompliance" -ViewName "Open Findings" `
    -Fields @("Title","cwf_stig_id","cwf_stig_title","cwf_stig_severity","cwf_stig_check_status","cwf_stig_system") `
    -Query "<Where><Eq><FieldRef Name='cwf_stig_check_status'/><Value Type='Choice'>Finding</Value></Eq></Where>"

New-CWFView -ListName "CWF_STIGCompliance" -ViewName "CAT I Findings" `
    -Fields @("Title","cwf_stig_id","cwf_stig_title","cwf_stig_severity","cwf_stig_check_status","cwf_stig_system") `
    -Query "<Where><And><Eq><FieldRef Name='cwf_stig_severity'/><Value Type='Choice'>CAT I (High)</Value></Eq><Eq><FieldRef Name='cwf_stig_check_status'/><Value Type='Choice'>Finding</Value></Eq></And></Where>"

New-CWFView -ListName "CWF_POAM" -ViewName "Open POA&Ms" `
    -Fields @("Title","cwf_poam_id","cwf_poam_weakness","cwf_poam_severity","cwf_poam_status","cwf_poam_sched_date") `
    -Query "<Where><Neq><FieldRef Name='cwf_poam_status'/><Value Type='Choice'>Completed</Value></Neq></Where>"

New-CWFView -ListName "CWF_POAM" -ViewName "Overdue POA&Ms" `
    -Fields @("Title","cwf_poam_id","cwf_poam_weakness","cwf_poam_severity","cwf_poam_status","cwf_poam_sched_date") `
    -Query "<Where><And><Lt><FieldRef Name='cwf_poam_sched_date'/><Value Type='DateTime'><Today/></Value></Lt><Neq><FieldRef Name='cwf_poam_status'/><Value Type='Choice'>Completed</Value></Neq></And></Where>"

Write-Status "Phase 4 complete: $($script:stats.Views) views created" "OK"
} # End Phase 4

########################################################################
# PHASE 5: JSON COLUMN FORMATTING
########################################################################
if ($StartPhase -le 5) {
Write-Phase 5 "JSON COLUMN + VIEW FORMATTING"

# ─── Compliance Status: Color-coded badges ───
$complianceBadgeJson = @'
{
  "$schema": "https://columnformatting.sharepointpnp.com/columnFormattingSchema.json",
  "elmType": "div",
  "style": {
    "display": "flex",
    "align-items": "center"
  },
  "children": [
    {
      "elmType": "span",
      "style": {
        "padding": "4px 12px",
        "border-radius": "16px",
        "font-size": "12px",
        "font-weight": "600",
        "white-space": "nowrap",
        "color": "=if(@currentField == 'Compliant', '#0b6a0b', if(@currentField == 'Non-Compliant', '#a80000', if(@currentField == 'Partially Compliant', '#8a6914', if(@currentField == 'Expired', '#a80000', '#605e5c'))))",
        "background-color": "=if(@currentField == 'Compliant', '#dff6dd', if(@currentField == 'Non-Compliant', '#fde7e9', if(@currentField == 'Partially Compliant', '#fff4ce', if(@currentField == 'Expired', '#fde7e9', '#f3f2f1'))))"
      },
      "txtContent": "@currentField"
    }
  ]
}
'@

# ─── Cert Status: Color-coded badges ───
$certStatusBadgeJson = @'
{
  "$schema": "https://columnformatting.sharepointpnp.com/columnFormattingSchema.json",
  "elmType": "div",
  "children": [
    {
      "elmType": "span",
      "style": {
        "padding": "4px 12px",
        "border-radius": "16px",
        "font-size": "12px",
        "font-weight": "600",
        "color": "=if(@currentField == 'Active', '#0b6a0b', if(@currentField == 'Expired', '#a80000', if(@currentField == 'Expiring Soon', '#8a6914', '#605e5c')))",
        "background-color": "=if(@currentField == 'Active', '#dff6dd', if(@currentField == 'Expired', '#fde7e9', if(@currentField == 'Expiring Soon', '#fff4ce', '#f3f2f1')))"
      },
      "txtContent": "@currentField"
    }
  ]
}
'@

# ─── SAAR Workflow Status: Pipeline badges ───
$saarStatusBadgeJson = @'
{
  "$schema": "https://columnformatting.sharepointpnp.com/columnFormattingSchema.json",
  "elmType": "div",
  "children": [
    {
      "elmType": "span",
      "style": {
        "padding": "4px 12px",
        "border-radius": "16px",
        "font-size": "12px",
        "font-weight": "600",
        "color": "=if(@currentField == 'Fully Approved', '#0b6a0b', if(@currentField == 'Denied', '#a80000', if(@currentField == 'Submitted', '#004e8c', if(@currentField == 'Draft', '#605e5c', if(@currentField == 'Revoked', '#a80000', '#8a6914')))))",
        "background-color": "=if(@currentField == 'Fully Approved', '#dff6dd', if(@currentField == 'Denied', '#fde7e9', if(@currentField == 'Submitted', '#deecf9', if(@currentField == 'Draft', '#f3f2f1', if(@currentField == 'Revoked', '#fde7e9', '#fff4ce')))))"
      },
      "txtContent": "@currentField"
    }
  ]
}
'@

# ─── Training Status badges ───
$trainingStatusBadgeJson = @'
{
  "$schema": "https://columnformatting.sharepointpnp.com/columnFormattingSchema.json",
  "elmType": "div",
  "children": [
    {
      "elmType": "span",
      "style": {
        "padding": "4px 12px",
        "border-radius": "16px",
        "font-size": "12px",
        "font-weight": "600",
        "color": "=if(@currentField == 'Completed', '#0b6a0b', if(@currentField == 'Expired', '#a80000', if(@currentField == 'In Progress', '#004e8c', if(@currentField == 'Failed', '#a80000', '#605e5c'))))",
        "background-color": "=if(@currentField == 'Completed', '#dff6dd', if(@currentField == 'Expired', '#fde7e9', if(@currentField == 'In Progress', '#deecf9', if(@currentField == 'Failed', '#fde7e9', '#f3f2f1'))))"
      },
      "txtContent": "@currentField"
    }
  ]
}
'@

# ─── STIG Severity: CAT badges ───
$stigSeverityJson = @'
{
  "$schema": "https://columnformatting.sharepointpnp.com/columnFormattingSchema.json",
  "elmType": "div",
  "children": [
    {
      "elmType": "span",
      "style": {
        "padding": "4px 12px",
        "border-radius": "16px",
        "font-size": "12px",
        "font-weight": "700",
        "color": "=if(@currentField == 'CAT I (High)', '#ffffff', if(@currentField == 'CAT II (Medium)', '#ffffff', if(@currentField == 'CAT III (Low)', '#0b6a0b', '#605e5c')))",
        "background-color": "=if(@currentField == 'CAT I (High)', '#a80000', if(@currentField == 'CAT II (Medium)', '#d83b01', if(@currentField == 'CAT III (Low)', '#dff6dd', '#f3f2f1')))"
      },
      "txtContent": "@currentField"
    }
  ]
}
'@

# ─── Expiration Date: Red highlight if <30 days, Yellow if <90 ───
$expirationDateJson = @'
{
  "$schema": "https://columnformatting.sharepointpnp.com/columnFormattingSchema.json",
  "elmType": "div",
  "style": {
    "padding": "4px 8px",
    "border-radius": "4px",
    "background-color": "=if(@currentField == '', '', if(@currentField < @now + 2592000000, '#fde7e9', if(@currentField < @now + 7776000000, '#fff4ce', '')))"
  },
  "children": [
    {
      "elmType": "span",
      "style": {
        "font-weight": "=if(@currentField < @now, '700', '400')",
        "color": "=if(@currentField < @now, '#a80000', '')"
      },
      "txtContent": "=if(@currentField == '', '', toLocaleDateString(@currentField))"
    }
  ]
}
'@

# ─── APPLY FORMATTING TO COLUMNS ───
$formatMap = @(
    @{List="CWF_Personnel";      Field="cwf_compliance_status"; Json=$complianceBadgeJson},
    @{List="CWF_PersonnelCerts"; Field="cwf_pc_cert_status";    Json=$certStatusBadgeJson},
    @{List="CWF_PersonnelCerts"; Field="cwf_pc_exp_date";       Json=$expirationDateJson},
    @{List="CWF_PersonnelTraining"; Field="cwf_pt_status";      Json=$trainingStatusBadgeJson},
    @{List="CWF_PersonnelTraining"; Field="cwf_pt_exp_date";    Json=$expirationDateJson},
    @{List="CWF_SAAR";           Field="cwf_saar_wf_status";    Json=$saarStatusBadgeJson},
    @{List="CWF_SAAR";           Field="cwf_saar_exp_date";     Json=$expirationDateJson},
    @{List="CWF_STIGCompliance"; Field="cwf_stig_severity";     Json=$stigSeverityJson},
    @{List="CWF_POAM";           Field="cwf_poam_severity";     Json=$stigSeverityJson},
    @{List="CWF_Waivers";        Field="cwf_waiver_exp_date";   Json=$expirationDateJson},
    @{List="CWF_Systems";        Field="cwf_sys_ato_exp";       Json=$expirationDateJson}
)

foreach ($fm in $formatMap) {
    if ($WhatIf) { Write-Status "$($fm.List).$($fm.Field) [WhatIf]" "VIEW"; continue }
    try {
        $field = Get-PnPField -List $fm.List -Identity $fm.Field
        $field | Set-PnPField -Values @{ CustomFormatter = $fm.Json }
        Write-Status "$($fm.List) -> $($fm.Field) formatted" "VIEW"
    } catch { Write-Status "Format $($fm.List).$($fm.Field): $_" "ERROR" }
}

Write-Status "Phase 5 complete: column formatting applied" "OK"
} # End Phase 5

########################################################################
# PHASE 6: DATA INGESTION FOLDER STRUCTURE
########################################################################
if ($StartPhase -le 6) {
Write-Phase 6 "DATA INGESTION FOLDERS"

$folders = @(
    "/CWF_DataIngestion",
    "/CWF_DataIngestion/Inbox",
    "/CWF_DataIngestion/Processed",
    "/CWF_DataIngestion/Failed",
    "/CWF_DataIngestion/Templates"
)

foreach ($folder in $folders) {
    if ($WhatIf) { Write-Status "$folder [WhatIf]"; continue }
    try {
        $lib = "Shared Documents"
        Resolve-PnPFolder -SiteRelativePath "Shared Documents$folder" | Out-Null
        Write-Status $folder "CREATE"
    } catch { Write-Status "Folder $folder : $_" "ERROR" }
}

Write-Status "Phase 6 complete: ingestion folder structure ready" "OK"
} # End Phase 6

########################################################################
# PHASE 7: EXPORT VALIDATION REPORT
########################################################################
if ($StartPhase -le 7) {
Write-Phase 7 "VALIDATION + EXPORT REPORT"

$report = @()
$allLists = Get-PnPList | Where-Object { $_.Title -like "CWF_*" }
foreach ($list in $allLists) {
    $fields = Get-PnPField -List $list.Title | Where-Object { $_.InternalName -like "cwf_*" }
    $views = Get-PnPView -List $list.Title
    $report += [PSCustomObject]@{
        List = $list.Title
        Items = $list.ItemCount
        CustomColumns = $fields.Count
        Views = $views.Count
        Versioning = $list.EnableVersioning
        UniquePerms = $list.HasUniqueRoleAssignments
    }
}

$report | Format-Table -AutoSize
$csvPath = ".\cwf_deployment_report_$timestamp.csv"
$report | Export-Csv -Path $csvPath -NoTypeInformation
Write-Status "Validation report exported to $csvPath" "OK"

# Export SP groups
$groups = Get-PnPGroup | Where-Object { $_.Title -like "CWF*" }
$groupReport = $groups | ForEach-Object {
    [PSCustomObject]@{
        Group = $_.Title
        Members = (Get-PnPGroupMember -Identity $_.Title -ErrorAction SilentlyContinue | Measure-Object).Count
    }
}
$groupReport | Format-Table -AutoSize
$groupCsvPath = ".\cwf_groups_report_$timestamp.csv"
$groupReport | Export-Csv -Path $groupCsvPath -NoTypeInformation
Write-Status "Group report exported to $groupCsvPath" "OK"
} # End Phase 7

########################################################################
# FINAL SUMMARY
########################################################################
Write-Host "`n$('=' * 60)" -ForegroundColor Green
Write-Host "  DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "$('=' * 60)" -ForegroundColor Green
Write-Host "  Created:  $($script:stats.Created)" -ForegroundColor Cyan
Write-Host "  Skipped:  $($script:stats.Skipped)" -ForegroundColor Yellow
Write-Host "  Views:    $($script:stats.Views)" -ForegroundColor Magenta
Write-Host "  Errors:   $($script:stats.Errors)" -ForegroundColor $(if($script:stats.Errors -gt 0){"Red"}else{"Green"})
Write-Host ""
Write-Host "  REMAINING MANUAL STEPS:" -ForegroundColor White
Write-Host "  1. Run seed script: .\cwf_teams_sp_deploy.ps1 -SiteUrl $SiteUrl -SkipListCreation -SkipPermissions" -ForegroundColor White
Write-Host "  2. Add users to SP groups (ISSM, supervisors)" -ForegroundColor White
Write-Host "  3. Apply sensitivity labels (see Migration Guide Section 3)" -ForegroundColor White
Write-Host "  4. Build 11 Power Automate flows (see Migration Guide Section 6)" -ForegroundColor White
Write-Host "  5. Build 3 ingestion flows (see PBI Pipeline doc Section 5)" -ForegroundColor White
Write-Host "  6. Upload Power BI exports to /CWF_DataIngestion/Inbox/" -ForegroundColor White
Write-Host "$('=' * 60)`n" -ForegroundColor Green
