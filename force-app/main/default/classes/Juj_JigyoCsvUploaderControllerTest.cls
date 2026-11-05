/**
 * Juj_JigyoCsvUploaderController のテストクラス
 */
@IsTest
private class Juj_JigyoCsvUploaderControllerTest {

    @IsTest
    static void getLoginUserInfo_returnsUserTypeAndSibuCode() {
        Test.startTest();
        Map<String, Object> result = Juj_JigyoCsvUploaderController.getLoginUserInfo();
        Test.stopTest();

        Assert.areEqual(Juj_JigyoCsvUploaderController.TEMP_USER_TYPE, result.get('userType'), 'ユーザ種別');
        Assert.areEqual(Juj_JigyoCsvUploaderController.TEMP_SIBU_CODE, result.get('sibuCode'), '支部コード');
    }

    @IsTest
    static void checkCategory2_simulate_returnsErrorsForEveryRow() {
        String requestJson = JSON.serialize(new Map<String, Object>{
            'jigyoList' => new List<Object>{
                new Map<String, Object>{
                    'key' => 'J001|01|2026',
                    'jigyoNo' => 'J001',
                    'basyoNo' => '01',
                    'nendo' => '2026',
                    'rows' => new List<Object>{
                        new Map<String, Object>{ 'fileKey' => 'jigyo', 'lineNo' => 2, 'data' => new Map<String, String>{ 'jigyoNo' => 'J001' } },
                        new Map<String, Object>{ 'fileKey' => 'meisai', 'lineNo' => 2, 'data' => new Map<String, String>() },
                        new Map<String, Object>{ 'fileKey' => 'meisai', 'lineNo' => 3, 'data' => new Map<String, String>() }
                    },
                    'csvResult' => new Map<String, String>()
                }
            }
        });

        Test.startTest();
        Map<String, Object> result = Juj_JigyoCsvUploaderController.checkCategory2(requestJson);
        Test.stopTest();

        List<Juj_JigyoCsvUploaderController.CheckError> errors =
            (List<Juj_JigyoCsvUploaderController.CheckError>) result.get('errors');
        Integer perRow = Juj_JigyoCsvUploaderController.SIMULATE_ERRORS_PER_ROW;
        Assert.areEqual(3 * perRow, errors.size(), '全行に 1 行 ' + perRow + ' 件');

        Juj_JigyoCsvUploaderController.CheckError first = errors[0];
        Juj_JigyoCsvUploaderController.CheckError expected = Juj_JigyoCsvUploaderController.SIMULATE_PATTERNS.get('jigyo')[0];
        Assert.areEqual('jigyo', first.fileKey, 'ファイル');
        Assert.areEqual(2, first.lineNo, '行番号');
        Assert.areEqual(expected.checkNo, first.checkNo, 'チェック No');
        Assert.areEqual(expected.messageId, first.messageId, 'メッセージ');
        Assert.areEqual(expected.x, first.x, '置換値');

        Juj_JigyoCsvUploaderController.CheckError meisaiLine3 = errors[3 * perRow - 1];
        Assert.areEqual('meisai', meisaiLine3.fileKey, 'ファイル');
        Assert.areEqual(3, meisaiLine3.lineNo, '行番号');
    }

    @IsTest
    static void checkCategory2_noJigyo_returnsNoError() {
        Map<String, Object> result = Juj_JigyoCsvUploaderController.checkCategory2('{}');
        Assert.areEqual(0, ((List<Juj_JigyoCsvUploaderController.CheckError>) result.get('errors')).size(), 'エラーなし');
    }
}
