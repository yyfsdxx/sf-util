/**
 * Juj_OubojouhoukensakuModelController のテストクラス
 * ※ テストデータの必須項目が不足する場合は setup に追加すること。
 */
@IsTest
private class Juj_OubojouhoukensakuModelControllerTest {

    private static final String JIGYO_NO = '0000001';
    private static final String BASYO_NO = '0000000001';
    private static final String NENDO = '2026';

    @TestSetup
    static void setup() {
        // 事務所・法人。支部コード・支部名は Jims_Sibu_Code__c・Jims_Sibu_Name__c（Name は使用しない）
        Account shibu1 = new Account(Name = 'テスト事務所A', Jims_Sibu_Code__c = '001', Jims_Sibu_Name__c = '東支部');
        Account shibu2 = new Account(Name = 'テスト事務所B', Jims_Sibu_Code__c = '002', Jims_Sibu_Name__c = '西支部');
        insert new List<Account>{ shibu1, shibu2 };

        Juji_Basyo_Master__c basyo = new Juji_Basyo_Master__c(
            JujM_Juji_Basyo_No__c = BASYO_NO,
            JujM_Juji_Basyo_Name__c = 'テスト場所'
        );
        insert basyo;
        Juji_Jigyo__c jigyo = new Juji_Jigyo__c(
            Juji_Juji_Jigyo_No__c = JIGYO_NO,
            Juji_Juji_Basyo_Master__c = basyo.Id,
            Juji_Jisi_Nendo__c = NENDO,
            Juji_Juji_Jigyo_Name__c = 'テスト事業',
            Juji_Jimusyo_Hojin__c = shibu1.Id
        );
        insert jigyo;

        // 会員（Contact）。支部は参照先の事務所・法人
        Contact m1 = new Contact(Kaii_Toroku_No__c = '1000001', LastName = '山田 太郎', AccountId = shibu1.Id);
        Contact m2 = new Contact(Kaii_Toroku_No__c = '1000002', LastName = '佐藤 花子', AccountId = shibu2.Id);
        insert new List<Contact>{ m1, m2 };
        Soudanin_Master__c s1 = new Soudanin_Master__c(SouM_Sodanin_No__c = '9000001', SouM_Sodanin_Name__c = '山田 一郎');
        insert s1;

        insert new List<Juji_Jigyo_Oubo__c>{
            new Juji_Jigyo_Oubo__c(Oubo_Juji_Jigyo__c = jigyo.Id, Oubo_Kaiin__c = m1.Id, Oubo_Uketuke_No__c = 2),
            new Juji_Jigyo_Oubo__c(Oubo_Juji_Jigyo__c = jigyo.Id, Oubo_Kaiin__c = m2.Id, Oubo_Uketuke_No__c = 1),
            new Juji_Jigyo_Oubo__c(Oubo_Juji_Jigyo__c = jigyo.Id, Oubo_Soudanin_Master__c = s1.Id, Oubo_Uketuke_No__c = 3)
        };
    }

    // ==================== ヘルパー ====================
    private static Juj_OubojouhoukensakuModelController.SearchCondition cond() {
        Juj_OubojouhoukensakuModelController.SearchCondition c = new Juj_OubojouhoukensakuModelController.SearchCondition();
        c.jujiJigyoNo = JIGYO_NO;
        c.jujiBasyoNo = BASYO_NO;
        c.jisiNendo = NENDO;
        return c;
    }

    // 画面と同じく JSON 文字列で検索処理を呼び出す
    private static List<Map<String, Object>> search(Juj_OubojouhoukensakuModelController.SearchCondition c) {
        return Juj_OubojouhoukensakuModelController.search(JSON.serialize(c));
    }

    // 各行の登録番号（相談員の場合は相談員番号）
    private static List<String> jujishaNos(List<Map<String, Object>> rows) {
        List<String> nos = new List<String>();
        for (Map<String, Object> row : rows) {
            String torokuNo = (String) row.get('torokuNo');
            nos.add(torokuNo != null ? torokuNo : (String) row.get('sodaninNo'));
        }
        return nos;
    }

    // ==================== 検索対象判定（5.データ更新 (7)③） ====================
    @IsTest
    static void search_条件なしは会員と相談員の両方を受付番号順() {
        List<Map<String, Object>> rows = search(cond());
        Assert.areEqual(new List<String>{ '1000002', '1000001', '9000001' }, jujishaNos(rows));
        Assert.areEqual('佐藤 花子', rows[0].get('name'));
        Assert.isNull(rows[0].get('sodaninNo'), '会員の場合、相談員番号は空白');
        Assert.isNull(rows[2].get('torokuNo'), '相談員の場合、登録番号は空白');
        Assert.areEqual('山田 一郎', rows[2].get('name'));
        Assert.isNotNull(rows[0].get('applicationId'));
        Assert.isNotNull(rows[0].get('createdDate'));
    }

    @IsTest
    static void search_未採番は末尾() {
        Soudanin_Master__c s2 = new Soudanin_Master__c(SouM_Sodanin_No__c = '9000002', SouM_Sodanin_Name__c = '鈴木 次郎');
        insert s2;
        // マイページからの応募（受付番号 0）
        insert new Juji_Jigyo_Oubo__c(
            Oubo_Juji_Jigyo__c = [SELECT Id FROM Juji_Jigyo__c LIMIT 1].Id,
            Oubo_Soudanin_Master__c = s2.Id,
            Oubo_Uketuke_No__c = 0
        );
        Assert.areEqual(new List<String>{ '1000002', '1000001', '9000001', '9000002' }, jujishaNos(search(cond())));
    }

    @IsTest
    static void search_会員側のみ入力は会員のみ() {
        Juj_OubojouhoukensakuModelController.SearchCondition c = cond();
        c.torokuNoFrom = '1000001';
        Assert.areEqual(new List<String>{ '1000002', '1000001' }, jujishaNos(search(c)));
    }

    @IsTest
    static void search_支部コードは会員のみ() {
        Juj_OubojouhoukensakuModelController.SearchCondition c = cond();
        c.shibuCodeFrom = '002';
        c.shibuCodeTo = '002';
        Assert.areEqual(new List<String>{ '1000002' }, jujishaNos(search(c)));
    }

    @IsTest
    static void search_相談員側のみ入力は相談員のみ() {
        Juj_OubojouhoukensakuModelController.SearchCondition c = cond();
        c.sodaninNoTo = '9999999';
        Assert.areEqual(new List<String>{ '9000001' }, jujishaNos(search(c)));
    }

    @IsTest
    static void search_両側入力はそれぞれの条件のOR() {
        Juj_OubojouhoukensakuModelController.SearchCondition c = cond();
        c.torokuNoFrom = '1000002';
        c.sodaninNoFrom = '9000001';
        Assert.areEqual(new List<String>{ '1000002', '9000001' }, jujishaNos(search(c)));
    }

    // ==================== 受付番号・氏名 ====================
    @IsTest
    static void search_受付番号範囲() {
        Juj_OubojouhoukensakuModelController.SearchCondition c = cond();
        c.uketukeNoFrom = 2;
        c.uketukeNoTo = 3;
        Assert.areEqual(new List<String>{ '1000001', '9000001' }, jujishaNos(search(c)));
    }

    @IsTest
    static void search_氏名部分一致は相談員側() {
        Juj_OubojouhoukensakuModelController.SearchCondition c = cond();
        c.name = '一郎';
        Assert.areEqual(new List<String>{ '9000001' }, jujishaNos(search(c)));
    }

    @IsTest
    static void search_氏名部分一致は会員側() {
        Juj_OubojouhoukensakuModelController.SearchCondition c = cond();
        c.name = '太郎';
        Assert.areEqual(new List<String>{ '1000001' }, jujishaNos(search(c)));
    }

    @IsTest
    static void search_氏名部分一致は会員・相談員の両方() {
        Juj_OubojouhoukensakuModelController.SearchCondition c = cond();
        c.name = '山田';
        Assert.areEqual(new List<String>{ '1000001', '9000001' }, jujishaNos(search(c)));
    }

    @IsTest
    static void escapeLike_特殊文字() {
        Assert.areEqual('a\\%b\\_c\\\\d', Juj_OubojouhoukensakuModelController.escapeLike('a%b_c\\d'));
    }

    // ==================== 事業の取得（No.36）・名称の取得（No.39） ====================
    @IsTest
    static void getJigyo_事業と場所名を取得() {
        Map<String, Object> r = Juj_OubojouhoukensakuModelController.getJigyo(JIGYO_NO, BASYO_NO, NENDO);
        Assert.areEqual('テスト場所', r.get('basyoName'));
        Map<String, Object> jigyo = (Map<String, Object>) r.get('jigyo');
        Assert.areEqual('テスト事業', jigyo.get('jigyoName'));
        Assert.areEqual('001', jigyo.get('shibuCode'));
        Assert.areEqual('東支部', jigyo.get('shibuName'), '支部名は Jims_Sibu_Name__c（Name ではない）');
    }

    @IsTest
    static void getJigyo_キー不足は場所名のみ() {
        Map<String, Object> r = Juj_OubojouhoukensakuModelController.getJigyo(null, BASYO_NO, NENDO);
        Assert.areEqual('テスト場所', r.get('basyoName'));
        Assert.isNull(r.get('jigyo'));
    }

    @IsTest
    static void getName_各種名称() {
        Assert.areEqual('山田 太郎', Juj_OubojouhoukensakuModelController.getName(Juj_OubojouhoukensakuModelController.NAME_TOROKU, '1000001'));
        Assert.areEqual('西支部', Juj_OubojouhoukensakuModelController.getName(Juj_OubojouhoukensakuModelController.NAME_SHIBU, '002'));
        Assert.areEqual('山田 一郎', Juj_OubojouhoukensakuModelController.getName(Juj_OubojouhoukensakuModelController.NAME_SODANIN, '9000001'));
    }

    @IsTest
    static void getName_未入力・該当なしはnull() {
        Assert.isNull(Juj_OubojouhoukensakuModelController.getName(Juj_OubojouhoukensakuModelController.NAME_TOROKU, ''));
        Assert.isNull(Juj_OubojouhoukensakuModelController.getName(Juj_OubojouhoukensakuModelController.NAME_TOROKU, '9999999'));
        Assert.isNull(Juj_OubojouhoukensakuModelController.getName(Juj_OubojouhoukensakuModelController.NAME_SHIBU, '999'));
        Assert.isNull(Juj_OubojouhoukensakuModelController.getName(Juj_OubojouhoukensakuModelController.NAME_SODANIN, '9999999'));
        Assert.isNull(Juj_OubojouhoukensakuModelController.getName('UNKNOWN', '1000001'));
    }

    // ==================== 0件・エラー ====================
    @IsTest
    static void search_事業なしは0件() {
        Juj_OubojouhoukensakuModelController.SearchCondition c = cond();
        c.jujiJigyoNo = '9999999';
        Assert.areEqual(0, search(c).size());
    }

    @IsTest
    static void search_事業キー未入力は0件() {
        Juj_OubojouhoukensakuModelController.SearchCondition c = cond();
        c.jisiNendo = null;
        Assert.areEqual(0, search(c).size());
    }

    @IsTest
    static void search_受付番号の範囲逆転はエラー() {
        Juj_OubojouhoukensakuModelController.SearchCondition c = cond();
        c.uketukeNoFrom = 3;
        c.uketukeNoTo = 1;
        try {
            search(c);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual('受付番号(From)は受付番号(To)以下の値を入力してください。', e.getMessage());
        }
    }

    @IsTest
    static void search_文字列の範囲逆転はエラー() {
        Juj_OubojouhoukensakuModelController.SearchCondition c = cond();
        c.torokuNoFrom = '2000000';
        c.torokuNoTo = '1000000';
        try {
            search(c);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual('登録番号(From)は登録番号(To)以下の値を入力してください。', e.getMessage());
        }
        c = cond();
        c.shibuCodeFrom = '002';
        c.shibuCodeTo = '001';
        try {
            search(c);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual('支部コード(From)は支部コード(To)以下の値を入力してください。', e.getMessage());
        }
        c = cond();
        c.sodaninNoFrom = '9000002';
        c.sodaninNoTo = '9000001';
        try {
            search(c);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual('相談員番号(From)は相談員番号(To)以下の値を入力してください。', e.getMessage());
        }
    }
}
