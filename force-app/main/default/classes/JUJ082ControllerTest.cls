/**
 * JUJ082Controller のテストクラス
 * ※ オブジェクト名・項目名は論理名で記載している（API 名確定後に一括置換する）。
 * ※ テストデータの必須項目が不足する場合は setup に追加すること。
 */
@IsTest
private class JUJ082ControllerTest {

    private static final String JIGYO_NO = '0000001';
    private static final String BASYO_NO = '0000000001';
    private static final String NENDO = '2026';

    @TestSetup
    static void setup() {
        // 事務所・法人（支部）。支部名＝Name、1つの支部コードに対応する支部は1件
        Account shibu1 = new Account(Name = '東支部', 支部コード__c = '001');
        Account shibu2 = new Account(Name = '西支部', 支部コード__c = '002');
        insert new List<Account>{ shibu1, shibu2 };

        従事場所マスタ__c basyo = new 従事場所マスタ__c(従事場所No__c = BASYO_NO, 従事場所名__c = 'テスト場所');
        insert basyo;
        従事事業__c jigyo = new 従事事業__c(
            従事事業No__c = JIGYO_NO,
            従事場所__c = basyo.Id,
            実施年度__c = NENDO,
            従事事業名__c = 'テスト事業',
            支部__c = shibu1.Id
        );
        insert jigyo;

        // 会員は取引先責任者（Contact）
        Contact m1 = new Contact(登録番号__c = '1000001', LastName = '山田 太郎', 事務所__c = shibu1.Id);
        Contact m2 = new Contact(登録番号__c = '1000002', LastName = '佐藤 花子', 事務所__c = shibu2.Id);
        insert new List<Contact>{ m1, m2 };
        相談員__c s1 = new 相談員__c(相談員番号__c = '9000001', 氏名__c = '山田 一郎');
        insert s1;
        // 【要確認】汎用マスタの対象年度
        insert new Hanyou_Master__c(対象年度__c = '2026');

        insert new List<従事事業応募__c>{
            new 従事事業応募__c(従事事業__c = jigyo.Id, 会員__c = m1.Id, 受付番号__c = 2),
            new 従事事業応募__c(従事事業__c = jigyo.Id, 会員__c = m2.Id, 受付番号__c = 1),
            new 従事事業応募__c(従事事業__c = jigyo.Id, 相談員__c = s1.Id, 受付番号__c = 3)
        };
    }

    // ==================== ヘルパー ====================
    private static JUJ082Controller.SearchCondition cond() {
        JUJ082Controller.SearchCondition c = new JUJ082Controller.SearchCondition();
        c.jujiJigyoNo = JIGYO_NO;
        c.jujiBasyoNo = BASYO_NO;
        c.jisiNendo = NENDO;
        return c;
    }

    // 画面と同じく JSON 文字列で検索処理を呼び出す
    private static List<Map<String, Object>> search(JUJ082Controller.SearchCondition c) {
        return JUJ082Controller.search(JSON.serialize(c));
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

    // ==================== 検索対象判定 ====================
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
    static void search_会員側のみ入力は会員のみ() {
        JUJ082Controller.SearchCondition c = cond();
        c.torokuNoFrom = '1000001';
        Assert.areEqual(new List<String>{ '1000002', '1000001' }, jujishaNos(search(c)));
    }

    @IsTest
    static void search_支部コードは会員のみ() {
        JUJ082Controller.SearchCondition c = cond();
        c.shibuCodeFrom = '002';
        c.shibuCodeTo = '002';
        Assert.areEqual(new List<String>{ '1000002' }, jujishaNos(search(c)));
    }

    @IsTest
    static void search_相談員側のみ入力は相談員のみ() {
        JUJ082Controller.SearchCondition c = cond();
        c.sodaninNoTo = '9999999';
        Assert.areEqual(new List<String>{ '9000001' }, jujishaNos(search(c)));
    }

    @IsTest
    static void search_両側入力はそれぞれの条件のOR() {
        JUJ082Controller.SearchCondition c = cond();
        c.torokuNoFrom = '1000002';
        c.sodaninNoFrom = '9000001';
        Assert.areEqual(new List<String>{ '1000002', '9000001' }, jujishaNos(search(c)));
    }

    // ==================== 共通条件・氏名 ====================
    @IsTest
    static void search_受付番号範囲() {
        JUJ082Controller.SearchCondition c = cond();
        c.uketukeNoFrom = 2;
        c.uketukeNoTo = 3;
        Assert.areEqual(new List<String>{ '1000001', '9000001' }, jujishaNos(search(c)));
    }

    @IsTest
    static void search_氏名部分一致は相談員側() {
        JUJ082Controller.SearchCondition c = cond();
        c.name = '一郎';
        Assert.areEqual(new List<String>{ '9000001' }, jujishaNos(search(c)));
    }

    @IsTest
    static void search_氏名部分一致は会員側() {
        JUJ082Controller.SearchCondition c = cond();
        c.name = '太郎';
        Assert.areEqual(new List<String>{ '1000001' }, jujishaNos(search(c)));
    }

    @IsTest
    static void search_氏名部分一致は会員・相談員の両方() {
        JUJ082Controller.SearchCondition c = cond();
        c.name = '山田';
        Assert.areEqual(new List<String>{ '1000001', '9000001' }, jujishaNos(search(c)));
    }

    @IsTest
    static void escapeLike_特殊文字() {
        Assert.areEqual('a\\%b\\_c\\\\d', JUJ082Controller.escapeLike('a%b_c\\d'));
    }

    // ==================== 実施年度の初期値・事業の取得・名称の取得 ====================
    @IsTest
    static void getDefaultNendo_汎用マスタの対象年度() {
        Assert.areEqual('2026', JUJ082Controller.getDefaultNendo());
    }

    @IsTest
    static void getJigyo_事業と場所名を取得() {
        Map<String, Object> r = JUJ082Controller.getJigyo(JIGYO_NO, BASYO_NO, NENDO);
        Assert.areEqual('テスト場所', r.get('basyoName'));
        Map<String, Object> jigyo = (Map<String, Object>) r.get('jigyo');
        Assert.areEqual('テスト事業', jigyo.get('jigyoName'));
        Assert.areEqual('001', jigyo.get('shibuCode'));
        Assert.areEqual('東支部', jigyo.get('shibuName'));
    }

    @IsTest
    static void getJigyo_キー不足は場所名のみ() {
        Map<String, Object> r = JUJ082Controller.getJigyo(null, BASYO_NO, NENDO);
        Assert.areEqual('テスト場所', r.get('basyoName'));
        Assert.isNull(r.get('jigyo'));
    }

    @IsTest
    static void getName_各種名称() {
        Assert.areEqual('山田 太郎', JUJ082Controller.getName(JUJ082Controller.NAME_TOROKU, '1000001'));
        Assert.areEqual('西支部', JUJ082Controller.getName(JUJ082Controller.NAME_SHIBU, '002'));
        Assert.areEqual('山田 一郎', JUJ082Controller.getName(JUJ082Controller.NAME_SODANIN, '9000001'));
    }

    @IsTest
    static void getName_未入力・該当なしはnull() {
        Assert.isNull(JUJ082Controller.getName(JUJ082Controller.NAME_TOROKU, ''));
        Assert.isNull(JUJ082Controller.getName(JUJ082Controller.NAME_TOROKU, '9999999'));
        Assert.isNull(JUJ082Controller.getName(JUJ082Controller.NAME_SHIBU, '999'));
        Assert.isNull(JUJ082Controller.getName(JUJ082Controller.NAME_SODANIN, '9999999'));
        Assert.isNull(JUJ082Controller.getName('UNKNOWN', '1000001'));
    }

    // ==================== 0件・エラー ====================
    @IsTest
    static void search_事業なしは0件() {
        JUJ082Controller.SearchCondition c = cond();
        c.jujiJigyoNo = '9999999';
        Assert.areEqual(0, search(c).size());
    }

    @IsTest
    static void search_事業キー未入力は0件() {
        JUJ082Controller.SearchCondition c = cond();
        c.jisiNendo = null;
        Assert.areEqual(0, search(c).size());
    }

    @IsTest
    static void search_範囲逆転はエラー() {
        JUJ082Controller.SearchCondition c = cond();
        c.uketukeNoFrom = 3;
        c.uketukeNoTo = 1;
        try {
            search(c);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(JUJ082Controller.E_RANGE[1], e.getMessage());
        }
    }

    @IsTest
    static void search_文字列範囲逆転はエラー() {
        JUJ082Controller.SearchCondition c = cond();
        c.torokuNoFrom = '2000000';
        c.torokuNoTo = '1000000';
        try {
            search(c);
            Assert.fail('例外が発生すること');
        } catch (AuraHandledException e) {
            Assert.areEqual(JUJ082Controller.E_RANGE[1], e.getMessage());
        }
    }
}
