package org.trebol.payment.impl.webpayplus;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.MockedConstruction;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;
import cl.transbank.webpay.webpayplus.WebpayPlus;
import cl.transbank.webpay.webpayplus.responses.WebpayPlusTransactionCommitResponse;
import cl.transbank.webpay.webpayplus.responses.WebpayPlusTransactionCreateResponse;
import org.trebol.api.models.PaymentRedirectionDetailsPojo;
import org.trebol.api.models.OrderPojo;
import org.trebol.payment.PaymentServiceException;
import org.trebol.testing.OrdersTestHelper;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.trebol.testing.TestConstants.ANY;

@ExtendWith(MockitoExtension.class)
class WebpayplusPaymentServiceImplTest {
    @InjectMocks WebpayplusPaymentServiceImpl instance;
    @Mock WebpayplusPaymentProperties propertiesMock;
    final OrdersTestHelper ordersHelper = new OrdersTestHelper();
    static final String RETURN_URL = "http://localhost";

    @BeforeEach
    void beforeEach() {
        ordersHelper.resetOrders();
    }

    @Nested
    class TestMode {
        @Test
        void fetches_payment_page_for_started_transactions() throws Exception {
            OrderPojo input = ordersHelper.orderPojoAfterCreation();
            when(propertiesMock.getCallbackUrl()).thenReturn(RETURN_URL);
            WebpayPlusTransactionCreateResponse createResponse = mock(WebpayPlusTransactionCreateResponse.class);
            when(createResponse.getToken()).thenReturn(ANY);
            when(createResponse.getUrl()).thenReturn(RETURN_URL);
            try (MockedConstruction<WebpayPlus.Transaction> ignored = Mockito.mockConstruction(
                WebpayPlus.Transaction.class,
                (mock, context) -> when(mock.create(anyString(), anyString(), anyDouble(), anyString()))
                    .thenReturn(createResponse))) {
                PaymentRedirectionDetailsPojo result = instance.requestNewPaymentPageDetails(input);
                assertNotNull(result);
                assertFalse(result.getToken().isBlank());
                assertFalse(result.getUrl().isBlank());
            }
        }

        @Test
        void fetches_payment_result() throws Exception {
            WebpayPlusTransactionCommitResponse commitResponse = mock(WebpayPlusTransactionCommitResponse.class);
            when(commitResponse.getResponseCode()).thenReturn((byte) 0);
            try (MockedConstruction<WebpayPlus.Transaction> ignored = Mockito.mockConstruction(
                WebpayPlus.Transaction.class,
                (mock, context) -> when(mock.commit(anyString())).thenReturn(commitResponse))) {
                assertDoesNotThrow(() -> instance.requestPaymentResult(ANY));
            }
        }

        @Test
        void fetches_payment_result_page_url() {
            when(propertiesMock.getBrowserRedirectionUrl()).thenReturn(ANY);
            String result = instance.getPaymentResultPageUrl();
            assertNotNull(result);
            assertEquals(ANY, result);
        }
    }

    @Nested
    class ProductionModeWithoutConfig {

        @BeforeEach
        void beforeEach() {
            when(propertiesMock.isProduction()).thenReturn(true);
        }

        @Test
        void will_not_begin_transactions() {
            OrderPojo input = ordersHelper.orderPojoAfterCreation();
            when(propertiesMock.getCallbackUrl()).thenReturn(RETURN_URL);
            PaymentServiceException result = assertThrows(PaymentServiceException.class, () -> instance.requestNewPaymentPageDetails(input));
            assertEquals("Webpay could not create a new transaction", result.getMessage());
        }

        @Test
        void will_not_fetch_transaction_result() throws PaymentServiceException {
            int result = instance.requestPaymentResult(ANY);
            assertEquals(1, result);
        }
    }
}
