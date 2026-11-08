// =====================================================================
// 従事事業CSV登録：オブジェクト定義・組織設定の追加確認（読み取りのみ。データは変更しない）
// 実行：開発者コンソール > Debug > Open Execute Anonymous Window に貼り付けて実行
//       ログを開き「#CHK2#」で絞り込む
// 確認事項（「35」G-14～G-22）：
//   G-14 Name 項目の型、G-15 既定値、G-16 ルックアップフィルタ・連動選択リスト、G-17 主従関係の共有設定、
//   G-19 数値・通貨の桁、G-20 重複ルール・承認プロセス・プロセスビルダー、G-21 組織の設定（タイムゾーン・通貨）、
//   G-22 既存の共通資産（カスタムメタデータ型・カスタム設定・共通 Apex）、G-6 支部コード 2 項目
// 権限・共有（OWD・プロファイル）は org 未整備のため対象外（G-18）
// =====================================================================

List<String> objs = new List<String>{
    'Juji_Jigyo__c', 'Juji_Jigyo_Meisai__c', 'Juji_Jigyo_Oubo__c',
    'Juji_Jigyo_Oubo_Meisai__c', 'Juji_Jigyo_Wariate__c', 'Juji_Jigyo_Jisseki__c'
};
Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();

for (String objName : objs) {
    Schema.DescribeSObjectResult od = gd.get(objName.toLowerCase()).getDescribe();
    Map<String, Schema.SObjectField> fm = od.fields.getMap();

    // G-14 Name 項目：自動採番でなければ登録時の Name の扱いを決める
    Schema.DescribeFieldResult nf = fm.get('name').getDescribe();
    System.debug('#CHK2# [NAME] ' + objName + ' | type=' + nf.getType() + ' | autoNumber=' + nf.isAutoNumber()
        + ' | nillable=' + nf.isNillable() + ' | defaultedOnCreate=' + nf.isDefaultedOnCreate() + ' | len=' + nf.getLength());

    for (String key : fm.keySet()) {
        Schema.DescribeFieldResult f = fm.get(key).getDescribe();
        if (!f.isCustom()) {
            continue;
        }
        String fname = objName + '.' + f.getName();
        Schema.DisplayType ft = f.getType();

        // G-15 既定値：項目の既定値・数式の既定値・選択リストの既定値
        Object dv = f.getDefaultValue();
        String dvf = f.getDefaultValueFormula();
        String pdv = null;
        if (ft == Schema.DisplayType.PICKLIST) {
            for (Schema.PicklistEntry pe : f.getPicklistValues()) {
                if (pe.isDefaultValue()) {
                    pdv = pe.getValue();
                }
            }
        }
        if (dv != null || dvf != null || pdv != null) {
            System.debug('#CHK2# [DEFAULT] ' + fname + ' | ' + f.getLabel() + ' | value=' + dv + ' | formula=' + dvf + ' | picklist=' + pdv);
        }

        // G-16 連動選択リスト：制御項目があれば CSV の組合せのチェックが必要か確認
        if (f.isDependentPicklist() && f.getController() != null) {
            System.debug('#CHK2# [DEPENDENT] ' + fname + ' | ' + f.getLabel() + ' | controller=' + f.getController().getDescribe().getName());
        }

        if (ft == Schema.DisplayType.REFERENCE) {
            // G-16 参照の検索条件：必須の検索条件は API の登録でもエラーになる
            Schema.FilteredLookupInfo fl = f.getFilteredLookupInfo();
            if (fl != null) {
                System.debug('#CHK2# [LOOKUP FILTER] ' + fname + ' | ' + f.getLabel() + ' | ref=' + f.getReferenceTo()
                    + ' | optional=' + fl.isOptionalFilter() + ' | dependent=' + fl.isDependent()
                    + ' | controllingFields=' + fl.getControllingFields());
            }
            // G-17 主従関係の共有設定：true＝親の参照権限で子を作成できる、false＝親の編集権限が必要
            if (f.getRelationshipOrder() != null) {
                System.debug('#CHK2# [MASTER_DETAIL] ' + fname + ' | ref=' + f.getReferenceTo()
                    + ' | writeRequiresMasterRead=' + f.isWriteRequiresMasterRead() + ' | reparentable=' + f.isUpdateable());
            }
        }

        // G-19 数値・通貨・パーセントの桁（全体桁数・小数桁数）
        if (ft == Schema.DisplayType.CURRENCY || ft == Schema.DisplayType.DOUBLE
            || ft == Schema.DisplayType.INTEGER || ft == Schema.DisplayType.PERCENT) {
            System.debug('#CHK2# [NUMBER] ' + fname + ' | ' + f.getLabel() + ' | type=' + ft
                + ' | precision=' + f.getPrecision() + ' | scale=' + f.getScale() + ' | digits=' + f.getDigits()
                + ' | calculated=' + f.isCalculated());
        }
        // テキストエリア・ロングテキストの桁
        if (ft == Schema.DisplayType.TEXTAREA) {
            System.debug('#CHK2# [TEXTAREA] ' + fname + ' | ' + f.getLabel() + ' | len=' + f.getLength());
        }
    }
}

// G-6 事務所・法人 の支部コード 2 項目（数式か・ヘルプテキスト）
Map<String, Schema.SObjectField> afm = Schema.SObjectType.Account.fields.getMap();
for (String key : new List<String>{ 'jims_sibu_code__c', 'jims_sibum_sibu_code__c' }) {
    if (afm.containsKey(key)) {
        Schema.DescribeFieldResult f = afm.get(key).getDescribe();
        System.debug('#CHK2# [ACCOUNT FIELD] ' + f.getName() + ' | ' + f.getLabel() + ' | type=' + f.getType()
            + ' | calculated=' + f.isCalculated() + ' | formula=' + f.getCalculatedFormula()
            + ' | help=' + f.getInlineHelpText());
    }
}

// G-20 重複ルール（登録をブロックする場合がある）
Set<String> objSet = new Set<String>(objs);
try {
    for (SObject r : Database.query('SELECT SobjectType, DeveloperName, MasterLabel, IsActive FROM DuplicateRule WHERE SobjectType IN :objSet')) {
        System.debug('#CHK2# [DUPLICATE RULE] ' + r.get('SobjectType') + ' | ' + r.get('DeveloperName') + ' | ' + r.get('MasterLabel') + ' | active=' + r.get('IsActive'));
    }
} catch (Exception e) {
    System.debug('#CHK2# [DUPLICATE RULE] 取得不可：' + e.getMessage());
}
// G-20 承認プロセス
try {
    for (SObject p : Database.query('SELECT Name, TableEnumOrId, State, Type FROM ProcessDefinition WHERE TableEnumOrId IN :objSet')) {
        System.debug('#CHK2# [APPROVAL] ' + p.get('TableEnumOrId') + ' | ' + p.get('Name') + ' | ' + p.get('State') + ' | ' + p.get('Type'));
    }
} catch (Exception e) {
    System.debug('#CHK2# [APPROVAL] 取得不可：' + e.getMessage());
}
// G-20 プロセスビルダー（ProcessType=Workflow）。ワークフロールールは Apex から取得できないため設定画面で確認
try {
    for (SObject fl : Database.query('SELECT ApiName, Label, ProcessType, IsActive FROM FlowDefinitionView WHERE IsActive = true AND ProcessType = \'Workflow\'')) {
        System.debug('#CHK2# [PROCESS BUILDER] ' + fl.get('ApiName') + ' | ' + fl.get('Label'));
    }
} catch (Exception e) {
    System.debug('#CHK2# [PROCESS BUILDER] 取得不可：' + e.getMessage());
}

// G-21 組織の設定（Asia/Tokyo 固定で日時を整形しているため確認。マルチ通貨なら通貨項目の扱いを確認）
Organization org = [SELECT Name, TimeZoneSidKey, LanguageLocaleKey, DefaultLocaleSidKey, IsSandbox, OrganizationType FROM Organization LIMIT 1];
System.debug('#CHK2# [ORG] ' + org.Name + ' | tz=' + org.TimeZoneSidKey + ' | lang=' + org.LanguageLocaleKey
    + ' | locale=' + org.DefaultLocaleSidKey + ' | sandbox=' + org.IsSandbox + ' | type=' + org.OrganizationType
    + ' | multiCurrency=' + UserInfo.isMultiCurrencyOrganization() + ' | currency=' + UserInfo.getDefaultCurrency()
    + ' | userTz=' + UserInfo.getTimeZone().getID());

// G-22 既存の共通資産：カスタムメタデータ型・カスタム設定（メッセージ管理 C-8、コード変換表 D-54 の参考）
for (String key : gd.keySet()) {
    Schema.DescribeSObjectResult d = gd.get(key).getDescribe();
    if (key.endsWith('__mdt')) {
        System.debug('#CHK2# [CUSTOM METADATA] ' + d.getName() + ' | ' + d.getLabel());
    } else if (d.isCustomSetting()) {
        System.debug('#CHK2# [CUSTOM SETTING] ' + d.getName() + ' | ' + d.getLabel());
    }
}
// G-22 共通 Apex（メッセージ・CSV・共通処理）
for (ApexClass c : [
    SELECT Name, NamespacePrefix FROM ApexClass
    WHERE NamespacePrefix = null AND (Name LIKE '%Common%' OR Name LIKE '%Csv%' OR Name LIKE '%Message%' OR Name LIKE '%Msg%'
        OR Name LIKE '%Util%' OR Name LIKE '%Const%' OR Name LIKE 'Com%')
    ORDER BY Name LIMIT 200
]) {
    System.debug('#CHK2# [APEX CLASS] ' + c.Name);
}
