// =====================================================================
// 従事事業CSV登録：マスタ・参照先オブジェクトの項目確認用（読み取りのみ。データは変更しない）
// 実行方法・出力の形式は juj_csv_object_check.apex と同じ（ログを「#CHK#」で絞り込む）
// 対象：従事場所マスタ・相談員マスタ・懲戒処分等履歴・銀行マスタ・銀行支店マスタ・汎用マスタ・事務所・法人（Account）・会員（Contact）の全カスタム項目
//       （事務所・法人・会員は標準項目のうち Name・ParentId・AccountId・RecordTypeId も出力）
// =====================================================================

List<String> objNames = new List<String>{
    'Juji_Basyo_Master__c', 'Soudanin_Master__c', 'Tyokai_Syobun_Rireki__c', 'Ginko_Master__c',
    'Ginko_Siten_Master__c', 'Hanyou_Master__c', 'Account', 'Contact'
};
Set<String> stdFields = new Set<String>{ 'name', 'parentid', 'accountid', 'recordtypeid', 'lastname', 'firstname' };

Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
for (String objName : objNames) {
    Schema.SObjectType t = gd.get(objName.toLowerCase());
    if (t == null) {
        System.debug('#CHK# [OBJ NOT FOUND] ' + objName);
        continue;
    }
    Schema.DescribeSObjectResult od = t.getDescribe();
    for (Schema.RecordTypeInfo rt : od.getRecordTypeInfos()) {
        if (!rt.isMaster()) {
            System.debug('#CHK# [RT] ' + objName + ' | ' + rt.getDeveloperName() + ' | ' + rt.getName() + ' | active=' + rt.isActive() + ' | default=' + rt.isDefaultRecordTypeMapping());
        }
    }
    Map<String, Schema.SObjectField> fm = od.fields.getMap();
    for (String key : fm.keySet()) {
        Schema.DescribeFieldResult f = fm.get(key).getDescribe();
        if (!f.isCustom() && !stdFields.contains(key)) {
            continue;
        }
        String line = objName + '.' + f.getName() + ' | ' + f.getLabel() + ' | ' + String.valueOf(f.getType()) + ' | len=' + f.getLength();
        if (!f.isNillable() && f.isCreateable() && !f.isDefaultedOnCreate() && f.getType() != Schema.DisplayType.BOOLEAN) {
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
