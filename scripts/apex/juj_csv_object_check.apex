// =====================================================================
// 従事事業CSV登録：オブジェクト・選択リストの確認用（読み取りのみ。データは変更しない）
// 実行：開発者コンソール > Debug > Open Execute Anonymous Window に貼り付けて実行
//       ログを開き「Debug Only」にチェック、または「#CHK#」で絞り込む
// 確認事項（「27」「35」）：D-21・D-53・C-4（選択リストの API 参照名）、D-23（数式）、E-8（必須項目）、
//                   C-11（トリガー・フロー）、D-31・D-52（支部の Account）、G-1（Contact の会員区分）、C-5（ログインユーザ）
// =====================================================================

// 対象オブジェクト → 対象項目（空の場合は全項目）
Map<String, Set<String>> targets = new Map<String, Set<String>>{
    'Juji_Jigyo__c' => new Set<String>(),
    'Juji_Jigyo_Meisai__c' => new Set<String>(),
    'Juji_Jigyo_Oubo__c' => new Set<String>(),
    'Juji_Jigyo_Oubo_Meisai__c' => new Set<String>(),
    'Juji_Jigyo_Wariate__c' => new Set<String>(),
    'Juji_Jigyo_Jisseki__c' => new Set<String>(),
    'Tyokai_Syobun_Rireki__c' => new Set<String>{ 'chok_tyokai_kubun__c', 'chok_kaiin__c', 'chok_toroku_no__c' },
    'Account' => new Set<String>{ 'jims_sibu_code__c', 'jims_sibu_kubun__c', 'jims_hojin_no__c', 'jims_hojin_no_edaban__c', 'jims_yuko_kikan_from__c', 'jims_yuko_kikan_to__c' },
    'Contact' => new Set<String>{ 'kaii_toroku_no__c', 'kaii_kaiin_kubun__c', 'kaii_taikai_zaikai__c' },
    'Soudanin_Master__c' => new Set<String>{ 'soum_sodanin_no__c', 'soum_tainin_nengapi__c' },
    'Ginko_Master__c' => new Set<String>{ 'ginm_ginko_code__c', 'ginm_yuko_kikan_from__c', 'ginm_yuko_kikan_to__c' },
    'Ginko_Siten_Master__c' => new Set<String>{ 'gism_ginko_code__c', 'gism_siten_code__c', 'gism_yuko_kikan_from__c', 'gism_yuko_kikan_to__c' }
};

Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
for (String objName : targets.keySet()) {
    Schema.SObjectType t = gd.get(objName.toLowerCase());
    if (t == null) {
        System.debug('#CHK# [OBJ NOT FOUND] ' + objName);
        continue;
    }
    Schema.DescribeSObjectResult od = t.getDescribe();
    // レコードタイプ
    for (Schema.RecordTypeInfo rt : od.getRecordTypeInfos()) {
        if (!rt.isMaster()) {
            System.debug('#CHK# [RT] ' + objName + ' | ' + rt.getDeveloperName() + ' | ' + rt.getName() + ' | active=' + rt.isActive() + ' | default=' + rt.isDefaultRecordTypeMapping());
        }
    }
    Set<String> only = targets.get(objName);
    Map<String, Schema.SObjectField> fm = od.fields.getMap();
    for (String key : fm.keySet()) {
        if (!only.isEmpty() && !only.contains(key)) {
            continue;
        }
        Schema.DescribeFieldResult f = fm.get(key).getDescribe();
        if (only.isEmpty() && !f.isCustom()) {
            continue;
        }
        String line = objName + '.' + f.getName() + ' | ' + f.getLabel() + ' | ' + String.valueOf(f.getType()) + ' | len=' + f.getLength();
        Boolean required = !f.isNillable() && f.isCreateable() && !f.isDefaultedOnCreate() && f.getType() != Schema.DisplayType.BOOLEAN;
        if (required) {
            line += ' | REQUIRED';
        }
        if (f.isUnique()) {
            line += ' | UNIQUE';
        }
        if (f.isExternalId()) {
            line += ' | EXTERNAL_ID';
        }
        if (f.getRelationshipOrder() != null) {
            line += ' | MASTER_DETAIL';
        }
        if (f.getType() == Schema.DisplayType.REFERENCE) {
            line += ' | ref=' + f.getReferenceTo() + ' rel=' + f.getRelationshipName();
        }
        System.debug('#CHK# [FIELD] ' + line);
        if (f.isCalculated() && f.getCalculatedFormula() != null) {
            System.debug('#CHK# [FORMULA] ' + objName + '.' + f.getName() + ' = ' + f.getCalculatedFormula().replace('\n', ' '));
        }
        if (f.getType() == Schema.DisplayType.PICKLIST || f.getType() == Schema.DisplayType.MULTIPICKLIST) {
            List<String> vals = new List<String>();
            for (Schema.PicklistEntry pe : f.getPicklistValues()) {
                vals.add('[' + pe.getValue() + ']=' + pe.getLabel() + (pe.isActive() ? '' : '(inactive)') + (pe.isDefaultValue() ? '(default)' : ''));
            }
            System.debug('#CHK# [PICKLIST] ' + objName + '.' + f.getName() + ' : ' + String.join(vals, ' ; ') + (f.isRestrictedPicklist() ? '  <restricted>' : '  <not restricted>'));
        }
    }
}

// トリガー（C-11）
Set<String> objNames = new Set<String>{ 'Juji_Jigyo__c', 'Juji_Jigyo_Meisai__c', 'Juji_Jigyo_Oubo__c', 'Juji_Jigyo_Oubo_Meisai__c', 'Juji_Jigyo_Wariate__c', 'Juji_Jigyo_Jisseki__c' };
for (ApexTrigger tr : [SELECT Name, TableEnumOrId, Status, UsageBeforeInsert, UsageAfterInsert, UsageBeforeUpdate, UsageAfterUpdate FROM ApexTrigger WHERE TableEnumOrId IN :objNames]) {
    System.debug('#CHK# [TRIGGER] ' + tr.TableEnumOrId + ' | ' + tr.Name + ' | ' + tr.Status
        + ' | bi=' + tr.UsageBeforeInsert + ' ai=' + tr.UsageAfterInsert + ' bu=' + tr.UsageBeforeUpdate + ' au=' + tr.UsageAfterUpdate);
}
// レコードトリガーフロー（C-11。取得できない環境ではスキップ）
try {
    for (SObject fl : Database.query('SELECT ApiName, Label, ProcessType, TriggerType, IsActive, TriggerObjectOrEventLabel FROM FlowDefinitionView WHERE IsActive = true AND TriggerType != null')) {
        System.debug('#CHK# [FLOW] ' + fl.get('TriggerObjectOrEventLabel') + ' | ' + fl.get('ApiName') + ' | ' + fl.get('Label') + ' | ' + fl.get('TriggerType'));
    }
} catch (Exception e) {
    System.debug('#CHK# [FLOW] 取得不可：' + e.getMessage());
}

// 支部の Account（D-31・D-52）：支部コードあり の件数（支部区分別）、支部コードの重複、本会（000）
for (AggregateResult ar : [SELECT Jims_sibu_kubun__c kubun, COUNT(Id) cnt FROM Account WHERE Jims_Sibu_Code__c != null GROUP BY Jims_sibu_kubun__c]) {
    System.debug('#CHK# [ACCOUNT 支部コードあり] 支部区分=' + ar.get('kubun') + ' 件数=' + ar.get('cnt'));
}
for (AggregateResult ar : [SELECT Jims_Sibu_Code__c code, COUNT(Id) cnt FROM Account WHERE Jims_Sibu_Code__c != null GROUP BY Jims_Sibu_Code__c HAVING COUNT(Id) > 1 LIMIT 20]) {
    System.debug('#CHK# [ACCOUNT 支部コード重複] ' + ar.get('code') + ' 件数=' + ar.get('cnt'));
}
for (Account a : [SELECT Name, Jims_Sibu_Code__c, Jims_sibu_kubun__c FROM Account WHERE Jims_sibu_kubun__c != null LIMIT 500]) {
    if (a.Jims_sibu_kubun__c.startsWith('0') || a.Jims_Sibu_Code__c == '000') {
        System.debug('#CHK# [ACCOUNT 本会] ' + a.Name + ' | 支部コード=' + a.Jims_Sibu_Code__c + ' | 支部区分=' + a.Jims_sibu_kubun__c);
    }
}

// Contact の会員区分（G-1：非会員が Contact にいるか）
for (AggregateResult ar : [SELECT Kaii_Kaiin_Kubun__c kubun, COUNT(Id) cnt FROM Contact WHERE Kaii_Toroku_No__c != null GROUP BY Kaii_Kaiin_Kubun__c]) {
    System.debug('#CHK# [CONTACT 会員区分] ' + ar.get('kubun') + ' 件数=' + ar.get('cnt'));
}

// 割当フラグの実データの値（D-21）
for (AggregateResult ar : [SELECT Wari_Wriate_Flag__c w, Wari_Kakutei_Flag__c k, COUNT(Id) cnt FROM Juji_Jigyo_Wariate__c GROUP BY Wari_Wriate_Flag__c, Wari_Kakutei_Flag__c LIMIT 20]) {
    System.debug('#CHK# [WARIATE フラグ実値] 割当=' + ar.get('w') + ' 確定=' + ar.get('k') + ' 件数=' + ar.get('cnt'));
}

// ログインユーザ（C-5）
Juj_CommonController.UserInitInfo info = Juj_CommonController.getLoginUserInfo();
System.debug('#CHK# [LOGIN USER] ' + UserInfo.getUserName() + ' | ' + JSON.serialize(info));
