public with sharing class WarehouseAllocateOrderAction {
    public class Request {
        public Request() {}

        @InvocableVariable(required=true label='Outbound Order Id' description='Outbound order to allocate from available warehouse inventory.')
        public Id orderId;
    }

    public class Response {
        public Response() {}

        @InvocableVariable(label='Outbound Order Id')
        public Id orderId;

        @InvocableVariable(label='Allocated Quantity')
        public Decimal allocatedQuantity;

        @InvocableVariable(label='Pick Task Count')
        public Integer pickTaskCount;

        @InvocableVariable(label='Order Status')
        public String orderStatus;
    }

    @InvocableMethod(
        label='Allocate Warehouse Orders'
        description='Reserves available warehouse inventory and creates pick tasks for outbound orders.'
    )
    public static List<Response> allocate(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return new List<Response>();
        }

        Set<Id> orderIds = new Set<Id>();
        for (Request request : requests) {
            if (request == null || request.orderId == null) {
                throw new WarehouseOutboundService.OutboundException('Every automation request requires an outbound order.');
            }
            orderIds.add(request.orderId);
        }

        Map<Id, WarehouseOutboundService.AllocationResult> allocationResults =
            WarehouseOutboundService.allocateOrders(orderIds);

        List<Response> responses = new List<Response>();
        for (Request request : requests) {
            WarehouseOutboundService.AllocationResult allocation = allocationResults.get(request.orderId);
            Response response = new Response();
            response.orderId = allocation.orderId;
            response.allocatedQuantity = allocation.allocatedQuantity;
            response.pickTaskCount = allocation.pickTaskCount;
            response.orderStatus = allocation.orderStatus;
            responses.add(response);
        }
        return responses;
    }
}
