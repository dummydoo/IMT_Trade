//+-------------------------------------------------------------------------------------+
//| Trade class file v1.0 MQL4                                                          |
//| A base class to place, close, modify, delete, and retrieve information about orders |
//| Copyright 2017 Infinite Mind Technologies                                           |
//+-------------------------------------------------------------------------------------+
#property copyright "Infinite Mind Technologies"
#property link      "http://www.infinitemindtechnologies.com"
#property version   "1.00"
#property strict

#include <stdlib.mqh>

#define MAX_RETRIES 3
#define RETRY_DELAY 3000
#define ADJUSTMENT_POINTS 5
#define SLEEP_TIME 10
#define MAX_CONTEXT_WAIT 30

struct TradeSettings{
   string symbol;
   double price;
   double volume;
   double stopLoss;
   double takeProfit;
   string comment;
   datetime expiration;
   color arrowColor;
   bool sltpInPoints;
   //Constructor to set default values
   TradeSettings(){price = 0.0; volume = 0.0; stopLoss = 0.0; takeProfit = 0.0; expiration = 0.0; arrowColor = clrNONE; sltpInPoints = true;}
};

class Trade{

   protected:
      int magicNumber;    //number to identify orders
      int slippage;       //max slippage for instant execution brokers
      bool TradingIsAllowed(void); //checks if the trade context is free and trading is allowed
      bool RetryOnError(int errorCode); //checks to see if an operation should be retried when an error is encountered
      string OrderTypeToString(int orderType); //returns the order type as a string
      double BuyStopLoss(string symbol, int stopPoints, double openPrice = 0.0); //calculates the stop loss price for a buy order (market or pending)
      double SellStopLoss(string symbol, int stopPoints, double openPrice = 0.0); //calculates the stop loss price for a sell order (market or pending)
      double BuyTakeProfit(string symbol, int stopPoints, double openPrice = 0.0); //calculates the take profit price for a buy order (market or pending)
      double SellTakeProfit(string symbol, int stopPoints, double openPrice = 0.0); //calculates the take profit price for a sell order (market or pending)
      double AdjustAboveStopLevel(string symbol, double price); //checks if a SL or TP price is too close to the bid/ask price and adjusts above if necessary
      double AdjustBelowStopLevel(string symbol, double price); //checks if a SL or TP price is too close to the bid/ask price and adjusts above if necessary
      bool ModifyOrder(int ticket, TradeSettings &orderSettings); //mofidies an existing order (market or pending)
      
   public:
      Trade(int mNumber); //constructor for the Trade class, takes the EA magic number as a parameter
      Trade(int mNumber, int slip); //overloaded constructor for instant execution brokers, takes the EA magic number and the desired slippage as parameters
      int GetMagicNumber(void); //returns the magic number stored in the class variable
      int GetSlippage(void); //returns the slippage value stored in the class variable (for instant execution brokers only)
      int TypeOfOrder(int ticket); //returns the type of an order, given the ticket number
};

//Constructors
Trade::Trade(int mNumber){
   magicNumber = mNumber;
   slippage = 0;
}

Trade::Trade(int mNumber, int slip){
   magicNumber = mNumber;
   //sanity check
   if(slip < 0)
      slippage = 0;
   else
      slippage = slip;
}

//Get the magic number that identifies the expert advisor
int Trade::GetMagicNumber(void){
   return magicNumber;
}

//Get the value stored in the slippage instance variable
int Trade::GetSlippage(void){
   return slippage;
}

//Check if the trade context is free and trading is allowed
bool Trade::TradingIsAllowed(void){
   // check whether the trade context is free
   if(!IsTradeAllowed()){
      uint startWaitingTime = GetTickCount();
      //only retry for the maximum context wait time
      while(GetTickCount() - startWaitingTime < MAX_CONTEXT_WAIT * 1000){
         //if the expert was terminated by the user, stop operation
         if(IsStopped())
            return false; 
         //if the trade context has become free, return true
         if(IsTradeAllowed())
            return true;
         //if no loop breaking condition has been met, "wait" for SLEEP_TIME and then restart checking
         Sleep(SLEEP_TIME);
      }
      //maximum context wait time exceeded, do not trade
      return false;
   }
   else
      return true;

}

//Check to see if we should retry on a given error
bool Trade::RetryOnError(int errorCode){
   switch(errorCode){
      case ERR_BROKER_BUSY:
      case ERR_COMMON_ERROR:
      case ERR_NO_ERROR:
      case ERR_NO_CONNECTION:
      case ERR_NO_RESULT:
      case ERR_SERVER_BUSY:
      case ERR_NOT_ENOUGH_RIGHTS:
      case ERR_MALFUNCTIONAL_TRADE:
      case ERR_TRADE_CONTEXT_BUSY:
      case ERR_TRADE_TIMEOUT:
      case ERR_REQUOTE:
      case ERR_TOO_MANY_REQUESTS:
      case ERR_OFF_QUOTES:
      case ERR_PRICE_CHANGED:
      case ERR_TOO_FREQUENT_REQUESTS:
         return true;
   }
   return false;
}

//Return the order type in a human-readable string
string Trade::OrderTypeToString(int orderType){
   string orderTypeDesc;
   if(orderType == OP_BUY)
      orderTypeDesc = "buy";
   else if(orderType == OP_SELL)
      orderTypeDesc = "sell";
   else if(orderType == OP_BUYSTOP)
      orderTypeDesc = "buy stop";
   else if(orderType == OP_SELLSTOP)
      orderTypeDesc = "sell stop";
   else if(orderType == OP_BUYLIMIT)
      orderTypeDesc = "buy limit";
   else if(orderType == OP_SELLLIMIT)
      orderTypeDesc = "sell limit";
   else
      orderTypeDesc = "invalid order type";
   
   return orderTypeDesc;
}

double Trade::BuyStopLoss(string symbol,int stopPoints,double openPrice=0.000000){
   //sanity check
   if(stopPoints <= 0 || openPrice < 0)
      return 0;
   //get the current price for the symbol if it is not supplied
   if(openPrice == 0)
      openPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
   //calculate the stop loss price
   double stopLoss = openPrice - (stopPoints * SymbolInfoDouble(symbol, SYMBOL_POINT));
   stopLoss = NormalizeDouble(stopLoss, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   
   return stopLoss;
}

double Trade::SellStopLoss(string symbol,int stopPoints,double openPrice=0.000000){
   //sanity check
   if(stopPoints <= 0 || openPrice < 0)
      return 0;
   //get the current price for the symbol if it is not supplied
   if(openPrice == 0)
      openPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
   //calculate the stop loss price
   double stopLoss = openPrice + (stopPoints * SymbolInfoDouble(symbol, SYMBOL_POINT));
   stopLoss = NormalizeDouble(stopLoss, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   
   return stopLoss;
}

double Trade::BuyTakeProfit(string symbol,int stopPoints,double openPrice=0.000000){
   //sanity check
   if(stopPoints <= 0 || openPrice < 0)
      return 0;
   //get the current price for the symbol if it is not supplied
   if(openPrice == 0)
      openPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
   //calculate the take profit price
   double takeProfit = openPrice + (stopPoints * SymbolInfoDouble(symbol, SYMBOL_POINT));
   takeProfit = NormalizeDouble(takeProfit, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   
   return takeProfit;
}

double Trade::SellTakeProfit(string symbol,int stopPoints,double openPrice=0.000000){
    //sanity check
   if(stopPoints <= 0 || openPrice < 0)
      return 0;
   //get the current price for the symbol if it is not supplied
   if(openPrice == 0)
      openPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
   //calculate the take profit price
   double takeProfit = openPrice - (stopPoints * SymbolInfoDouble(symbol, SYMBOL_POINT));
   takeProfit = NormalizeDouble(takeProfit, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   
   return takeProfit;
}

double Trade::AdjustAboveStopLevel(string symbol,double price){
   //get the current price for the symbol
   double currentPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
   //get the point value for the symbol
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   //calculate the minimum stop distance
   double stopLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   //check if the stop price needs to be adjusted
   if(price > currentPrice + stopLevel)
      return price;
   //calculate the number of points to adjust the stop by
   double addPoints = ADJUSTMENT_POINTS * point;
   //adjust the stop price
   price = currentPrice + stopLevel + addPoints;
   price = NormalizeDouble(price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   Print("Price adjusted above stop level to ",price," for ",symbol);
   return price;
}

double Trade::AdjustBelowStopLevel(string symbol,double price){
   //get the current price for the symbol
   double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
   //get the point value for the symbol
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   //calculate the minimum stop distance
   double stopLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   //check if the stop price needs to be adjusted
   if(price < currentPrice - stopLevel)
      return price;
   //calculate the number of points to adjust the stop by
   double addPoints = ADJUSTMENT_POINTS * point;
   //adjust the stop price
   price = currentPrice - stopLevel - addPoints;
   price = NormalizeDouble(price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   Print("Price adjusted below stop level to ",price," for ",symbol);
   return price;
}

bool Trade::ModifyOrder(int ticket,TradeSettings &orderSettings){
   int retryCount = 0;
   bool orderModified = false;
   int errorCode;
   string errorDesc, errorMsg, successMsg;
   bool serverError;
   
   //submit order to server
   do{
      //check if trading is allowed on the symbol and the trade context is free
      if(TradingIsAllowed()){
         //modify the order
         orderModified = OrderModify(ticket, orderSettings.price, orderSettings.stopLoss, orderSettings.takeProfit, orderSettings.expiration, orderSettings.arrowColor);
      }
      //error handling - ignore no change
      errorCode = GetLastError();
      if(!orderModified && errorCode != ERR_NO_RESULT){
         errorDesc = ErrorDescription(errorCode);
         serverError = RetryOnError(errorCode);
         //fatal error
         if(serverError == false){
            errorMsg = NULL;
            StringConcatenate(errorMsg, "Modify order: Error ",errorCode," - ",errorDesc,". Symbol: ",orderSettings.symbol,", Price: ",orderSettings.price,", SL: ",
               orderSettings.stopLoss,", TP: ",orderSettings.takeProfit,", Expiration: ",orderSettings.expiration);
            Alert(errorMsg);
            break;
         }
         //server error, retry...
         else{
            Print("Server error ",errorCode," - ",errorDesc," encountered, retrying...");
            Sleep(RETRY_DELAY);
            retryCount++;
         }
      }//end error handling
      //modify order successful - includes no change case
      else{
         StringConcatenate(successMsg, "Order #",ticket," modified.");
         Comment(successMsg);
         StringConcatenate(successMsg, " Symbol: ",orderSettings.symbol,", Price: ",orderSettings.price,", SL: ",
               orderSettings.stopLoss,", TP: ",orderSettings.takeProfit,", Expiration: ",orderSettings.expiration);
         Print(successMsg);
         break;
      }
   }while(retryCount < MAX_RETRIES);
   //failed after retries
   if(retryCount >= MAX_RETRIES){
      errorMsg = NULL;
      StringConcatenate(errorMsg, "Modify order: Max retries exceeded. Error ",errorCode," - ",errorDesc);
      Alert(errorMsg);
   }
   
   return orderModified;
}

int Trade::TypeOfOrder(int ticket){
   bool orderSelected = OrderSelect(ticket, SELECT_BY_TICKET);
   if(!orderSelected){
      Print("TypeOfOrder: order #",ticket," not found!");
      return -1;
   }
   
   return OrderType();
}
