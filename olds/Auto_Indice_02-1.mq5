//+------------------------------------------------------------------+
//|                                             Auto_Indice_02-1.mq5 |
//|                        Copyright 2018, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2018, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#include <Trade\Trade.mqh>

#define MA_MAGIC 737868954850

CTrade Trade;
ENUM_ORDER_TYPE signal = WRONG_VALUE;
MqlRates ratesDay[];

input ulong INP_VOLUME = 2;
double   pivot;
double   R1, R2, S1, S2;
double breakeven  = 150;
double target = 300;
double rp = 0;
int      hilo = -1;   //0: azul | 1: vermelho
MqlRates rates[];
MqlTick  lastTick;
bool     Hedging = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
        int copiedRates = CopyRates(_Symbol, PERIOD_D1, 0, 3, ratesDay);
        ArraySetAsSeries(ratesDay, true);
        double maxima = ratesDay[1].high;
        double minima = ratesDay[1].low;
        double close = ratesDay[1].close;
        
        // Hedging recebe "true" se a conta for hegding ou "false" se for netting:
        Hedging = ((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
        Print("Conta Hegding: ", Hedging);
        
        // Define o ID do Robô:
        Trade.SetExpertMagicNumber(MA_MAGIC);
        
        // Calcula o pivot point:
        pivot = PivotPoint(maxima, minima, close);
        
        // Calcula os dois níveis de resistência com base no pivot point:
        R1 = ResistenciaNivel_01(minima);
        R2 = ResistenciaNivel_02(maxima, minima);
        
        // Calcula os dois níveis de suporte com base no pivot point:
        S1 = SuporteNivel_01(maxima); 
        S2 = SuporteNivel_02(maxima, minima);
         
        // Imprime dados calculados:       
        Print("Pivot Point: ", pivot);
        Print("Resis. 1: ", R1);
        Print("Resis. 2: ", R2);
        Print("Suporte 1: ", S1);
        Print("Suporte 2: ", S2);   
         
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
      
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
      double MMeRed[];        // Buffer que armazena os valores da média que representa o hilo vermelho. 
      double MMeBlue[];       // Buffer que armazena os valores da media que representa o hilo azul.
      
      // Define as propriedades da média móvel exponencial de 9 periodos e deslocamento de 1.
      int movingAverageRed = iMA(_Symbol, _Period, 24, 1, MODE_EMA, PRICE_HIGH);
      // Define as propriedades da média móvel exponencial de 9 periodos sem o deslocamento.
      int movingAverageBlue = iMA(_Symbol, _Period, 24, 1, MODE_EMA, PRICE_LOW);
      
      // Recupera os valores dos ultimos 5 candles:
      int copied = CopyRates(_Symbol, _Period, 0, 5, rates);
      
      // Inverte a posição do Array para o preço mais recente ficar na posição 0.
      ArraySetAsSeries(rates, true);
      ArraySetAsSeries(MMeRed, true);
      ArraySetAsSeries(MMeBlue, true);            
      
      // Obtem dados do buffer de um indicador no caso das médias móveis:
      if(CopyBuffer(movingAverageRed, 0, 0, 3, MMeRed) != 3){
         Print("Erro CopyBuffer, Erro ao recuperar dados da MMeRed!", GetLastError());
         return;
      }
      if(CopyBuffer(movingAverageBlue, 0, 0, 3, MMeBlue) != 3){
         Print("Erro CopyBuffer, Erro ao recuperar dados da MMeBlue!", GetLastError());
         return;         
      }
      
      // Modifica o Hilo de acordo com o fechamento da barra anterior.
      AtualizaHilo(MMeRed[1], MMeBlue[1]);
      
      // Recupera informações no preço atual (do tick):
      if(!SymbolInfoTick(_Symbol, lastTick)){
         Print("Erro ao obter a informação do preço: ", GetLastError());
         return;
      }
      
      signal = ContaBarra();
      
      /*//////////////////////////////////////////////////////////////////////////////
      /                           ENTRADA NA COMPRA                                 //
      *///////////////////////////////////////////////////////////////////////////////      
      if( (hilo == 0) && (signal == ORDER_TYPE_BUY) && (lastTick.ask < R1) && (lastTick.ask > rates[1].high) && (VerificaTipoPosicao() != POSITION_TYPE_BUY)){
         Print("Estratégia de Compra Acionada...");
         // Verifica se há posição em aberto se sim elimina a posição.
         if( (PositionsTotal() > 0) || OrdersTotal() > 0 ){
            if(!EliminaPosicao() && !EliminaOrdem()){
               Print("Erro ao eliminar Posição ! - ", GetLastError() );
            }else{
                 RealizaCompra();
               }
         }else{
             RealizaCompra();
          }     
      }
      
      /*//////////////////////////////////////////////////////////////////////////////
      /                           ENTRADA NA VENDA                                  //
      *///////////////////////////////////////////////////////////////////////////////
      if( (hilo == 1) && (signal == ORDER_TYPE_SELL) && (lastTick.bid > S1) && (lastTick.bid < rates[1].low) && (VerificaTipoPosicao() != POSITION_TYPE_SELL)){
         Print("Estratégia de Venda Acionada...");
         // Verifica se há posição em aberto se sim elimina a posição.
         if( (PositionsTotal() > 0) || OrdersTotal() > 0 ){
            if(!EliminaPosicao() && !EliminaOrdem()){
               Print("Erro ao eliminar Posição ! - ", GetLastError() );
            }else
              RealizaVenda(); 
         }else
            RealizaVenda(); 
      }
      
      // Verifica se o preço atingiu o valor de realização parcial:
      if(lastTick.last == rp){
         Print("Breakeven acionado...", rp);
         // Executa Realização Parcial se a quantidade de volume for divisível por dois:
         if(INP_VOLUME%2 == 0)
            if(!RealizaParcial())
               Print("Erro de Realização Parcial !!!");
         //Executa Elevação do StopLoss:
         if(!EvoluiStop())
            Print("Erro ao Evoluir Stop !!!");
      }      
  }
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| Expert Realiza Venda function                                    |
//+------------------------------------------------------------------+
void RealizaVenda(){
//--- Realiza Venda se for uma conta Hedging:
   if(Hedging){
      Print("Conta Hedging !!!");
      if(SellMarket(rates[1].high)){
         Print("Venda Acionada...");
      }else
         Print("Erro ao realizar a Venda !: ", GetLastError());
      }
//--- Realiza a Venda se for uma conta Netting:   
   else{
      Print("Conta Netting !!!");
      SellMarket(rates[1].high);
   }
}
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| Expert Realiza Compra function                                   |
//+------------------------------------------------------------------+
void RealizaCompra(){
//--- Realiza Compra se for uma conta Hedging:
   if(Hedging){
      Print("Conta Hedging !!!");
      if(BuyMarket(rates[1].low)){
         Print("Compra Acionada...");
      }else
         Print("Erro ao realizar a Venda !: ", GetLastError());
      }
//--- Realiza a Compra se for uma conta Netting:   
   else{
      Print("Conta Netting !!!");
      BuyMarket(rates[1].low);
   }
}
//+------------------------------------------------------------------+



//+------------------------------------------------------------------+
//| Expert Buy function                                              |
//+------------------------------------------------------------------+
bool BuyMarket(double _minima){
   Print("Compra em ask: ", lastTick.ask);
   Print("Mínima Candle ant: ", _minima );
   bool ok = Trade.Buy(INP_VOLUME, _Symbol, lastTick.ask, _minima, lastTick.ask + 300);
   rp = lastTick.last + breakeven;
   if(!ok){
      int errorCode = GetLastError();
      Print("BuyMarket: ", errorCode);
      ResetLastError();
   }
   return ok;
}
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| Expert Sell function                                             |
//+------------------------------------------------------------------+
bool SellMarket(double _maxima){
   Print("Venda em bid: ", lastTick.bid);
   Print("Máxima Candle ant: ", _maxima);
   bool ok = Trade.Sell(INP_VOLUME, _Symbol, lastTick.bid, _maxima, lastTick.bid - 300);
   rp = lastTick.last - breakeven;
   if(!ok){
      int errorCode = GetLastError();
      Print("SellMarket: ", errorCode);
      ResetLastError();
   }
   return ok;
}
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| Expert Pivot Point function                                      |
//+------------------------------------------------------------------+
double PivotPoint(double _price_max, double _price_min, double _price_close){
   // Retorna o Pivot Point:
   return ((_price_max + _price_min + _price_close) / 3);
}
//+------------------------------------------------------------------+



//+------------------------------------------------------------------+
//| Expert Resistência 1 function                                    |
//+------------------------------------------------------------------+
double ResistenciaNivel_01(double _price_min){
   // Retorna a primeira resistência:
   return (2 * pivot - _price_min);
}
//+------------------------------------------------------------------+



//+------------------------------------------------------------------+
//| Expert Resistência 2 function                                    |
//+------------------------------------------------------------------+
double ResistenciaNivel_02(double _price_max, double _price_min){
   // Retorna a segunda resistência:
   return (pivot + (_price_max - _price_min));
}
//+------------------------------------------------------------------+



//+------------------------------------------------------------------+
//| Expert Suporte 1 function                                        |
//+------------------------------------------------------------------+
double SuporteNivel_01(double _price_max){
   // Retorna a segunda resistência:
   return (2 * pivot - _price_max);
}
//+------------------------------------------------------------------+



//+------------------------------------------------------------------+
//| Expert Suporte 2 function                                        |
//+------------------------------------------------------------------+
double SuporteNivel_02(double _price_max, double _price_min){
   // Retorna a segunda resistência:
   return (pivot - (_price_max - _price_min));
}
//+------------------------------------------------------------------+



//+------------------------------------------------------------------+
//| Expert Atualiza Hilo function                                    |
//+------------------------------------------------------------------+
void AtualizaHilo(double _mediaVerm, double _mediaAzul){
      // Verifica a virada do Hilo:
      if(rates[1].close > _mediaVerm){
         hilo = 0;
      }
      else if(rates[1].close <_mediaAzul){
         hilo = 1;
      }     
}
//+------------------------------------------------------------------+



//+------------------------------------------------------------------+
//| Expert Atualiza Hilo function                                    |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE ContaBarra(){
      int conta_max = 0;
      int conta_min = 0;
      ENUM_ORDER_TYPE sinal = WRONG_VALUE;
      
      // Verifica se rompe máxima ou mínima dos últimos 5 candles:    
      for(int index = 0; index < ArraySize(rates); index++){
         //Print("Max[",index ,"]: ", rates[index].high);
         if(lastTick.ask > rates[index].high)
            conta_max++;
         if(lastTick.bid < rates[index].low)
            conta_min++;
      }
  
      if(conta_max > 0)
         sinal = ORDER_TYPE_BUY;
      else if(conta_min > 0)
            sinal = ORDER_TYPE_SELL;
      
      return sinal;
      
}
//+------------------------------------------------------------------+



//+------------------------------------------------------------------+
//| Expert Verifica Posição function                                 |
//+------------------------------------------------------------------+
bool VerificaPosicao(){
   bool res=false;
//--- check position in Hedging mode
   if(Hedging)
     {
      uint total=PositionsTotal();
      for(uint i=0; i<total; i++)
        {
         string position_symbol=PositionGetSymbol(i);
         if(_Symbol==position_symbol && MA_MAGIC == PositionGetInteger(POSITION_MAGIC))
           {
            res=true;
            break;
           }
        }
     }
//--- check position in Netting mode
   else
     {
      if(!PositionSelect(_Symbol))
         return(false);
      else
         return(PositionGetInteger(POSITION_MAGIC) == MA_MAGIC); //---check Magic number
     }
//--- result for Hedging mode
   return(res);
}
//+------------------------------------------------------------------+



//+------------------------------------------------------------------+
//| Expert verifica tipo Posição function                            |
//+------------------------------------------------------------------+
ENUM_POSITION_TYPE VerificaTipoPosicao(){

ENUM_POSITION_TYPE res = WRONG_VALUE;

   // Verifica a posição em uma conta Hedging:
   if(Hedging)
     {
      uint total=PositionsTotal();
      for(uint i=0; i<total; i++)
        {
         string position_symbol=PositionGetSymbol(i);
         if(_Symbol==position_symbol && MA_MAGIC == PositionGetInteger(POSITION_MAGIC))
           {
              if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY){
               res = POSITION_TYPE_BUY;
               break;
              }
              else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL){
               res = POSITION_TYPE_SELL;
               break;
              } 
           }
        }
     }
   // Verifica a posição em um conta Netting:
   else
     {
      if(!PositionSelect(_Symbol))
         return(WRONG_VALUE);
      else{
         if(PositionGetInteger(POSITION_MAGIC) == MA_MAGIC) //---check Magic number
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY){
               return POSITION_TYPE_BUY;
            }
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL){
               return POSITION_TYPE_SELL;
            }
         }
     }
//--- result for Hedging mode
   return(res);
}

//+------------------------------------------------------------------+



//+------------------------------------------------------------------+
//| Expert Elimina Ordem function                                    |
//+------------------------------------------------------------------+
bool EliminaOrdem(){
   bool res=false;
   uint total=OrdersTotal();
   ulong orderTicket = 0;

      for(uint i=0; i<total; i++)
        {
         orderTicket = OrderGetTicket(i);
         if(MA_MAGIC == OrderGetInteger(ORDER_MAGIC))
           {
             return Trade.OrderDelete(orderTicket);  
             break;  
           }
        }
     return res; 
}
//+------------------------------------------------------------------+



//+------------------------------------------------------------------+
//| Expert Elimina Posição function                                  |
//+------------------------------------------------------------------+
bool EliminaPosicao(){
   bool res=true;
//--- check position in Hedging mode
   if(Hedging)
     {
      uint total=PositionsTotal();
      for(uint i=0; i<total; i++)
        {
         string position_symbol=PositionGetSymbol(i);
         if(_Symbol==position_symbol && MA_MAGIC==PositionGetInteger(POSITION_MAGIC))
           {
             return(Trade.PositionClose(_Symbol));
             break;  
           }
        }
     }
//--- check position in Netting mode
   else
     {
      if(PositionSelect(_Symbol))
         if(PositionGetInteger(POSITION_MAGIC)==MA_MAGIC) //---check Magic number
         {
            return(Trade.PositionClose(_Symbol));
         }
      else{
         return false;
      }
     }
//--- result for Hedging mode
   return(res);   
}
//+------------------------------------------------------------------+



//+------------------------------------------------------------------+
//| Expert Realização Parcial function                               |
//+------------------------------------------------------------------+
bool RealizaParcial(){
   bool res=false;
//--- check position in Hedging mode
   if(Hedging)
     {
      uint total=PositionsTotal();
      for(uint i=0; i<total; i++)
        {
         string position_symbol=PositionGetSymbol(i);
         if(_Symbol == position_symbol && MA_MAGIC == PositionGetInteger(POSITION_MAGIC))
           {
             if(!Trade.PositionClosePartial(_Symbol, (INP_VOLUME/2), 150)){
               Print("Erro Real. Parcial: ", GetLastError());
               return false;
               break;
             }else{
               return true;
               break;
              }  
           }
        }
     }
//--- check position in Netting mode
   else
     {
      if(!PositionSelect(_Symbol))
         return(false);
      else{
         if(PositionGetInteger(POSITION_MAGIC) == MA_MAGIC) //---check Magic number
         {  
            Print("Magic Number: ", MA_MAGIC);
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY){
               if(!Trade.Sell((INP_VOLUME/2), _Symbol, lastTick.bid, NULL, NULL)){
                  Print("Erro Real. Parcial: ", GetLastError());
                  return false;
               }else
                  return true;
            }else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL){
               if(!Trade.Buy((INP_VOLUME/2), _Symbol, lastTick.ask, NULL, NULL)){
                  Print("Erro Real. Parcial: ", GetLastError());
                  return false;
               }else
                  return true;
            }
            
         }
      }
     }
//--- result for Hedging mode
   return(res);     
}
//+------------------------------------------------------------------+



//+------------------------------------------------------------------+
//| Expert Evolui Stop function                                      |
//+------------------------------------------------------------------+
bool EvoluiStop(){
   bool res=false;
//--- check position in Hedging mode
   if(Hedging)
     {
      uint total=PositionsTotal();
      for(uint i=0; i<total; i++)
        {
         string position_symbol=PositionGetSymbol(i);
         if(_Symbol == position_symbol && MA_MAGIC == PositionGetInteger(POSITION_MAGIC))
           {
             // Recupera o preço de entrada da posição:
             double novostop = PositionGetDouble(POSITION_PRICE_OPEN);  
             // Eleva o preço de stop para o preço de entrada: 
             if(!Trade.PositionModify(_Symbol, novostop , PositionGetDouble(POSITION_TP) )){
               Print("Erro Real. Parcial: ", GetLastError());
               return false;
               break;
             }else{
               return true;
               break;
              }  
           }
        }
     }
//--- check position in Netting mode
   else
     {
      if(!PositionSelect(_Symbol))
         return(false);
      else{
         if(PositionGetInteger(POSITION_MAGIC) == MA_MAGIC) //---check Magic number
         {  
            Print("Magic Number: ", MA_MAGIC);
            // Recupera o preço de entrada da posição:
            double novostop = PositionGetDouble(POSITION_PRICE_OPEN);  
            if(!Trade.PositionModify(_Symbol, novostop , PositionGetDouble(POSITION_TP))){
               Print("Erro Real. Parcial: ", GetLastError());
               return false;
            }else
               return true;
         }
      }
     }
//--- result for Hedging mode
   return(res);      
}
//+------------------------------------------------------------------+